# Hot-Load Analysis: Can `Gem::Installer#load_plugin` Solve the Chicken-and-Egg Problem?

**TL;DR — No, not directly.** The hot-load fires during **installation**, but
the failure occurs during **resolution**, which runs first. However, the
hot-load mechanism opens the door to a **metadata-based two-phase approach**
that could make single-command `gem install my-gem` work.

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

**Hot-load: too late.** Resolution fails before install begins.

Even if resolution somehow passed, two additional blockers exist:
1. `ApiSpecPatch` (which synthesizes specs from Compact Index data instead of
   the missing Marshal endpoint) isn't loaded yet.
2. `DownloadPatch` (for clear namespace download errors) isn't loaded yet.

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

**For `gem install` (Use Case 1):** Implement **Approach A** (metadata-based
deps + `done_installing` hook). This is the only approach that reliably enables
single-command `gem install my-gem` via the hot-load mechanism. The
`rubygems_plugin.rb` already registers hooks at load time; adding a
`done_installing` hook that processes `metadata["namespaced_dependencies"]` is
a natural extension.

**For Bundler (all use cases):** The current architecture is already correct.
The `BundlerIntegration` TracePoint-based deferred patching handles URI deps
in `add_dependency` seamlessly. **No changes needed.**

**For `gem install` of direct URI names** (`gem install @kaspth/oaken`):
The hot-load is irrelevant here (the plugin must already be installed). This
path depends on the server serving `/gems/` under the namespace path
(ISSUE.md). No change from current status.

### Next Steps

1. Create `lib/namespaced/gem/metadata_deps_hook.rb` implementing a
   `Gem.done_installing` hook that reads `namespaced_dependencies` from
   installed specs' metadata and triggers a second install pass.
2. Wire it into `rubygems_plugin.rb` alongside the existing patches.
3. Document the `metadata["namespaced_dependencies"]` convention for gem
   authors who want single-command `gem install` support.
4. Keep `add_dependency` URI support for the Bundler path (it works today).
5. Consider whether gem authors should use a helper method
   (`Namespaced::Gem.add_namespaced_dependency(spec, uri, version)`) that
   writes both `add_dependency` and `metadata` automatically.

---

## The Hot-Load Mechanism IS Valuable — Just Not for Resolution

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
past the initial resolution and handled by hooks after the plugin is live. This
is a viable, if non-standard, architecture for bridging the gap until RubyGems
natively supports source-qualified dependency names.
