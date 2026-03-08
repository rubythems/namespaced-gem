# Hot-Load Analysis: Can `Gem::Installer#load_plugin` Solve the Chicken-and-Egg Problem?

**TL;DR — The hot-load alone cannot solve the cold-start resolution problem
(resolution runs before installation), but it enables a metadata-based
two-phase approach via `MetadataDepsHook`. More importantly, when the plugin is
pre-installed (the common case), all `gem install` paths work today — including
direct `gem install @kaspth/oaken`.**

---

## The Chicken-and-Egg Problem (recap)

When a user runs `gem install my-gem` and `my-gem`'s gemspec contains:

```ruby
spec.add_dependency "namespaced-gem"
spec.add_dependency "https://beta.gem.coop/@myspace/foo", "~> 1.0"
```

…and `namespaced-gem` is **not yet installed**, the patches from
`rubygems_plugin.rb` are not loaded. RubyGems sees the URI string as a literal
gem name, queries rubygems.org for it, finds nothing, and aborts.

---

## Exact `gem install` Execution Sequence

```
gem install my-gem
  │
  ├─ 1. BOOT — Gem.load_plugins / Gem.load_env_plugins
  │      └─ Only loads rubygems_plugin.rb from ALREADY-INSTALLED gems
  │         └─ namespaced-gem NOT installed → NO patches loaded
  │
  ├─ 2. RESOLVE — DependencyInstaller#resolve_dependencies
  │      ├─ Fetches my-gem's spec from rubygems.org
  │      ├─ Sees deps: ["namespaced-gem", "https://beta.gem.coop/@myspace/foo"]
  │      ├─ Tries to look up "https://beta.gem.coop/@myspace/foo" on rubygems.org
  │      ├─ No match found
  │      └─ ❌ ABORTS — resolution fails BEFORE any gem is installed
  │
  └─ 3. INSTALL (never reached)
         ├─ Would install namespaced-gem first (leaf dep, via TSort)
         ├─ Gem::Installer#load_plugin would fire
         ├─ rubygems_plugin.rb would be require'd into running process
         ├─ All patches would activate
         └─ my-gem install would proceed with patches active
```

**The hot-load fires at step 3, but the failure is at step 2.**

The resolution phase (`RequestSet#resolve`) runs in its entirety before
`RequestSet#install` begins. The `InstallerSet#find_all` method encounters the
URI dependency string, has no patch to intercept it, queries the default source
(rubygems.org), finds no gem by that name, and the resolver aborts with
`Gem::UnsatisfiableDependencyError`.

---

## Impact on Each Use Case

### Use Case 1: Gem Authors (`gem install my-gem`, first time)

**Hot-load: too late for cold-start.** When the plugin is NOT pre-installed,
resolution fails before install begins.

However, when the plugin IS pre-installed (Use Cases 2–4), `gem install my-gem`
with URI deps in the gemspec **works today** — `GemResolverPatch` intercepts
the resolver, `ApiSpecPatch` synthesizes specs from Compact Index data, and
`DownloadPatch` handles namespace download errors.

**For the Bundler path** (`bundle install` with `gemspec`), the hot-load is
**irrelevant** — the existing `BundlerIntegration` TracePoint approach already
handles this. Bundler loads `Bundler::Dsl`, the TracePoint fires, patches
activate, and URI deps are remapped before Bundler's own resolution begins.
This path works today.

### Use Case 2: Application Developers (pre-installed)

**Hot-load: irrelevant.** The plugin is already installed (via
`gem install namespaced-gem`), so `rubygems_plugin.rb` loads at boot via
`Gem.load_plugins`. The patches are active before any gemspec is evaluated.

### Use Case 3: Global Installation (pre-installed)

**Same as Use Case 2.** Plugin already in gem path. Hot-load not involved.

---

## What the Hot-Load CAN Do

While the hot-load can't fix the resolution-phase failure, it **does** enable:

1. **`post_install` / `done_installing` hooks** — After `namespaced-gem` is
   installed as a leaf dependency (in a separate install invocation, or as part
   of a successful resolution that didn't include URI deps), hooks registered
   by `rubygems_plugin.rb` fire for all subsequent gems in the same batch.

2. **Mid-batch patch activation** — If `namespaced-gem` is installed as part
   of a batch (e.g. `gem install namespaced-gem other-gem`), the hot-load
   activates all patches before `other-gem`'s install phase. However, the
   **resolution** for the entire batch still happened before any installs, so
   this only helps if `other-gem` doesn't have URI deps that need resolving
   (or if they were resolved via other means).

---

## Viable Approaches Leveraging the Hot-Load Discovery

### Approach A: Metadata-Based Two-Phase Resolution (recommended)

Instead of putting URI deps directly in `add_dependency` (which must survive
resolution on rubygems.org), encode them in `spec.metadata`:

```ruby
# Published gemspec on rubygems.org
Gem::Specification.new do |spec|
  spec.name    = "my-gem"
  spec.version = "1.0.0"

  # namespaced-gem is a normal runtime dep — resolves fine on rubygems.org
  spec.add_dependency "namespaced-gem"

  # URI deps stored in metadata — invisible to RubyGems' resolver
  spec.metadata["namespaced_dependencies"] = [
    "https://beta.gem.coop/@myspace/foo ~> 1.0",
    "@myorg/bar >= 2.0"
  ].join("\n")

  # Normal deps work as usual
  spec.add_dependency "rack", "~> 3.0"
end
```

The flow becomes:

```
gem install my-gem
  │
  ├─ 1. BOOT — no namespaced-gem installed → no patches
  │
  ├─ 2. RESOLVE — sees deps: ["namespaced-gem", "rack"]
  │      └─ ✅ All plain names — resolves fine on rubygems.org
  │
  ├─ 3. INSTALL (topological order)
  │      ├─ Install namespaced-gem (leaf dep)
  │      │    └─ load_plugin fires → rubygems_plugin.rb loaded
  │      │         └─ All patches activate
  │      │         └─ done_installing hook registers
  │      ├─ Install rack
  │      └─ Install my-gem
  │           └─ post_install hook fires
  │                └─ Reads spec.metadata["namespaced_dependencies"]
  │                └─ Parses URI deps
  │                └─ Triggers second resolution pass for URI deps
  │                     (patches are now active!)
  │                └─ Installs namespace-sourced gems
  │
  └─ 4. DONE — all gems installed ✅
```

**This is the only approach that enables single-command `gem install my-gem`
without pre-installation of the plugin.**

#### Implementation sketch

A new `MetadataDepsHook` module, loaded by `rubygems_plugin.rb`, would:

1. Register a `Gem.done_installing` hook (or `Gem.post_install` per-gem).
2. After each gem installs, check `spec.metadata["namespaced_dependencies"]`.
3. If present, parse the URI dep strings and trigger a
   `Gem::DependencyInstaller` for each, with all patches now active.

#### Trade-offs

- **Pro:** Single-command install works. No pre-installation required.
- **Pro:** Compatible with the hot-load mechanism — patches activate before
  the hook fires.
- **Con:** URI deps are not visible in the standard `add_dependency` list.
  Tools that inspect gemspec dependencies won't see them.
- **Con:** Requires gem authors to use `metadata` instead of (or in addition
  to) `add_dependency` for URI deps — a less intuitive API.
- **Con:** The second resolution pass is a separate install; version conflicts
  between the first and second pass must be handled.

### Approach B: Dual Encoding (best of both worlds)

Gem authors use **both** `add_dependency` (for Bundler, which handles URI deps
via `BundlerIntegration`) **and** `metadata` (for `gem install`, via the
hot-load hook):

```ruby
Gem::Specification.new do |spec|
  spec.add_dependency "namespaced-gem"

  # For Bundler (handled by BundlerIntegration patch):
  spec.add_dependency "https://beta.gem.coop/@myspace/foo", "~> 1.0"

  # For gem install (handled by done_installing hook after hot-load):
  spec.metadata["namespaced_dependencies"] = \
    "https://beta.gem.coop/@myspace/foo ~> 1.0"
end
```

When `gem install my-gem` runs:
- Resolution ignores the URI dep (rubygems.org returns no match, but the gem
  itself still resolves because the URI dep is not "required" for resolution to
  complete — **this needs verification**; if the resolver hard-fails on
  unresolvable deps, this won't work).

**⚠️ Problem:** RubyGems' resolver will try to resolve ALL `add_dependency`
entries. An unresolvable URI dep causes `Gem::UnsatisfiableDependencyError`
and aborts the entire resolution. Dual encoding only works if we can teach
the resolver to **skip** URI deps during resolution and defer them.

This could be done with a minimal boot-time shim (see Approach C).

### Approach C: Minimal Boot-Time Shim (no full plugin needed)

Ship a **second, tiny gem** (`namespaced-gem-shim`) that contains only a
`rubygems_plugin.rb` with a single patch: teach `InstallerSet#find_all` to
**silently skip** URI-named deps during resolution (returning an empty array
instead of failing). The full `namespaced-gem` plugin then handles actual
installation via the `done_installing` hot-load hook.

```ruby
# namespaced-gem-shim/lib/rubygems_plugin.rb
# This gem is tiny and can be pre-installed globally, or it can be the
# gem that gets hot-loaded.

# Teach the resolver to not crash on URI dep names.
module NamespacedGemShim
  module InstallerSetSkipUri
    def find_all(req)
      return [] if req.name.match?(%r{\Ahttps?://|^@[^/]+/|^pkg:gem/})
      super
    end
  end
end

Gem::Resolver::InstallerSet.prepend(NamespacedGemShim::InstallerSetSkipUri)
```

With this shim installed:
1. Resolution encounters the URI dep, `find_all` returns `[]`, resolver
   treats it as an optional/unsatisfiable dep (depending on `type`).
2. All other deps resolve normally.
3. `namespaced-gem` installs as a leaf dep, hot-loads full patches.
4. `done_installing` hook processes the URI deps that were skipped.

**⚠️ Problem:** Runtime deps are not optional — the resolver will still fail
if it can't satisfy a required dep. The shim would need to also patch the
resolver's conflict-handling to treat URI deps as "deferred" rather than
"missing."

---

## Verdict

| Approach | Single-command install? | Gem author API | Complexity |
|----------|----------------------|----------------|------------|
| **A: Metadata only** | ✅ Yes | `metadata` field (non-standard) | Medium |
| **B: Dual encoding** | ❌ Resolver aborts on URI dep | Both `add_dependency` + `metadata` | High |
| **C: Shim gem** | ⚠️ Depends on resolver skip | Standard `add_dependency` | Very High |
| **Pre-install** (status quo) | Requires 2 commands | Standard `add_dependency` | None |

### Recommendation

**For `gem install` (Use Cases 2–4, plugin pre-installed):** This **already
works**. `GemResolverPatch` intercepts URI deps during resolution,
`ApiSpecPatch` synthesizes specs from Compact Index data (bypassing the missing
Marshal endpoint), and the namespace server serves `/gems/` for downloads.

**For `gem install my-gem` (Use Case 1, cold-start):** **Approach A** has been
implemented as `MetadataDepsHook` (metadata-based deps + `done_installing`
hook). This enables single-command `gem install my-gem` via the hot-load
mechanism when gem authors encode URI deps in
`spec.metadata["namespaced_dependencies"]`.

**For Bundler (all use cases):** The current architecture is already correct.
The `BundlerIntegration` TracePoint-based deferred patching handles URI deps
in `add_dependency` seamlessly. **No changes needed.**

**For `gem install` of direct URI names** (`gem install @kaspth/oaken`):
This **works today** (plugin must be pre-installed). The namespace server
serves both the Compact Index and `/gems/` endpoints.

### Implementation Status (completed)

1. ✅ `lib/namespaced/gem/metadata_deps_hook.rb` — `Gem.done_installing` hook
   that reads `namespaced_dependencies` from installed specs' metadata and
   triggers a second install pass.
2. ✅ Wired into `rubygems_plugin.rb` alongside existing patches (step 6).
3. ✅ `Namespaced::Gem.add_namespaced_dependency(spec, uri, version)` helper
   that writes both `add_dependency` and `metadata` automatically.
4. ✅ `add_dependency` URI support works for both the Bundler and
   `gem install` paths (when plugin is pre-installed).

---

## The Hot-Load Mechanism IS Valuable

The discovery in HOT_HOOK.md is genuinely important. It confirms that:

1. `rubygems_plugin.rb` files hot-load during `gem install` via
   `Gem::Installer#load_plugin` — this is a documented, reliable RubyGems
   feature.
2. TSort-based topological install order guarantees the plugin gem installs
   before dependents.
3. Hooks registered by the hot-loaded plugin (`pre_install`, `post_install`,
   `done_installing`) are active for all subsequent gems in the batch.
4. The hot-load fires only on first install (`find_all_by_name.size == 1`) —
   upgrades don't re-trigger it (the next boot picks up the new version).

The key insight is that **hooks fire post-install, not post-resolve**. The
hot-load enables a **second-phase install** pattern where URI deps are deferred
past the initial resolution and handled by hooks after the plugin is live.
This pattern is implemented in `MetadataDepsHook` and enables the cold-start
`gem install my-gem` path (when the gem author uses
`spec.metadata["namespaced_dependencies"]`).

For the pre-installed plugin case (Use Cases 2–4), the hot-load is not needed —
the plugin loads at boot and all patches are active for the entire `gem install`
pipeline, including resolution. **Both `gem install @kaspth/oaken` and
`gem install my-gem` (with URI deps in the gemspec) work today.**
