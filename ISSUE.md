# gem.coop namespace servers missing legacy Marshal API endpoints required by `gem install`

## Summary

`beta.gem.coop` namespace servers implement only the **Compact Index** API
(used by Bundler), but not the **legacy Marshal API** (used by `gem install`).
This means `gem install @kaspth/oaken` fails even when the
[namespaced-gem](https://gitlab.com/galtzo-floss/namespaced-gem) plugin is
installed and correctly intercepts the resolver.

A secondary issue: the production `gem.coop` server returns **HTTP 200 with
body `"404"`** for namespace endpoints, instead of a proper HTTP 404 status
code.

---

## Context

The `namespaced-gem` RubyGems plugin enables gemspec dependencies to be declared
as full URIs (e.g. `spec.add_dependency "https://beta.gem.coop/@kaspth/oaken"`).
It patches both Bundler and RubyGems' native resolver to parse these URIs,
derive the namespace source URL, and resolve against it.

Each namespace (e.g. `https://beta.gem.coop/@kaspth/`) is treated as its own
**discrete gem server** — completely independent of the root server or any
other namespace.

---

## What works: Compact Index (Bundler)

The Compact Index endpoints are served correctly under namespace paths.
Bundler uses **only** these two endpoints, so `bundle install` / `bundle lock`
works today.

| Endpoint | URL | Status |
|---|---|---|
| `versions` | `https://beta.gem.coop/@kaspth/versions` | ✅ 200 — returns gem listing |
| `info/{gem}` | `https://beta.gem.coop/@kaspth/info/oaken` | ✅ 200 — returns per-version dependency data |

---

## What's missing: Legacy Marshal API (`gem install`)

When `gem install` resolves a dependency, it uses RubyGems' native resolver
(`Gem::DependencyInstaller` → `Gem::Resolver::InstallerSet`). The flow is:

1. **Discovery** — `Gem::Source#dependency_resolver_set` probes
   `{source}/versions`. Since that returns 200, it creates an `APISet` backed
   by `{source}/info/`. This step **succeeds** — the gem and its versions are
   found via the Compact Index.

2. **Spec fetch** — `InstallerSet#add_always_install` calls
   `APISpecification#spec`, which calls `Gem::Source#fetch_spec`. This method
   constructs the URL:

   ```
   {source}/quick/Marshal.4.8/{gem}-{version}.gemspec.rz
   ```

   and expects a **deflated (`Zlib`) Marshal-serialized `Gem::Specification`**
   in response. This endpoint **returns 404**.

3. **Gem download** — After resolution, RubyGems downloads the `.gem` file
   from:

   ```
   {source}/gems/{gem}-{version}.gem
   ```

   This endpoint also **returns 404**.

4. **Crash** — The 404 HTML body is passed to `Zlib::Inflate.inflate`, which
   raises `Zlib::DataError: incorrect header check`.

### Endpoints that return 404 (all under the namespace path)

| Endpoint | URL | Expected response |
|---|---|---|
| `quick/Marshal.4.8/{gem}-{ver}.gemspec.rz` | `https://beta.gem.coop/@kaspth/quick/Marshal.4.8/oaken-2.5.1.gemspec.rz` | Deflated Marshal-serialized `Gem::Specification` |
| `gems/{gem}-{ver}.gem` | `https://beta.gem.coop/@kaspth/gems/oaken-2.5.1.gem` | The `.gem` file |
| `specs.4.8.gz` | `https://beta.gem.coop/@kaspth/specs.4.8.gz` | Gzipped Marshal array of all `[name, version, platform]` tuples |
| `latest_specs.4.8.gz` | `https://beta.gem.coop/@kaspth/latest_specs.4.8.gz` | Gzipped Marshal array of latest `[name, version, platform]` tuples |

**All of these must be served under the namespace path** (e.g.
`https://beta.gem.coop/@kaspth/quick/…`, not `https://beta.gem.coop/quick/…`),
because each namespace is its own discrete gem server.

The minimum required for `gem install` to work are:

1. **`quick/Marshal.4.8/{gem}-{ver}.gemspec.rz`** — the gemspec, serialized
   with `Marshal.dump` then compressed with `Zlib::Deflate.deflate`.
2. **`gems/{gem}-{ver}.gem`** — the `.gem` package file for download.

---

## Reproduction

### Direct install

```bash
# Requires Ruby >= 3.2, RubyGems >= 4.0.5
gem install namespaced-gem   # install the plugin first

gem install @kaspth/oaken    # shorthand (defaults to https://gem.coop)
# => ERROR: Zlib::DataError — incorrect header check

gem install https://beta.gem.coop/@kaspth/oaken   # full URI
# => ERROR: Zlib::DataError — incorrect header check
```

### Transitive dependency (Use Case 1)

Even when the plugin is already installed, `gem install` of a gem whose gemspec
contains URI dependencies also fails:

```bash
gem install namespaced-gem   # plugin loaded on next boot

gem install my-gem           # my-gem.gemspec has:
                             #   spec.add_dependency "https://beta.gem.coop/@kaspth/oaken", "~> 1.0"
```

The resolution phase succeeds — the `InstallerSetPatch#find_all` intercept
correctly remaps the URI dep and queries the compact index. But the
**installation phase** fails because RubyGems downloads `.gem` files from
`{source}/gems/{name}-{version}.gem`, which returns 404.

Additionally, there is a **chicken-and-egg problem** for first-time installs:
if `namespaced-gem` is listed as a dependency of `my-gem` (rather than being
pre-installed), the plugin is not loaded when `gem install my-gem` starts —
because RubyGems loads `rubygems_plugin.rb` files only from _already installed_
gems at boot. In this case, RubyGems encounters the URI dependency string
without the patches in place and tries to look it up as a literal gem name on
rubygems.org, failing immediately.

### Full stack trace (direct install)

```
ERROR:  While executing gem ... (Zlib::DataError)
    incorrect header check
        .../rubygems/util.rb:47:in 'Zlib::Inflate.inflate'
        .../rubygems/util.rb:47:in 'Gem::Util.inflate'
        .../rubygems/source.rb:132:in 'Gem::Source#fetch_spec'
        .../rubygems/resolver/api_specification.rb:93:in 'Gem::Resolver::APISpecification#spec'
        .../rubygems/resolver/installer_set.rb:99:in 'Gem::Resolver::InstallerSet#add_always_install'
        .../rubygems/dependency_installer.rb:243:in 'Gem::DependencyInstaller#resolve_dependencies'
        .../rubygems/commands/install_command.rb:198:in 'Gem::Commands::InstallCommand#install_gem'
        ...
```

---

## Impact: which code paths work today

| Scenario | API used | Works? |
|---|---|---|
| `bundle lock` / `bundle install` with URI deps in gemspec | Compact Index only | ✅ |
| `bundler/inline` with a namespace source block | Compact Index only | ✅ |
| `gem install @kaspth/oaken` (direct) | Marshal API + gem download | ❌ |
| `gem install my-gem` (transitive URI deps, plugin pre-installed) | Marshal API + gem download | ❌ |
| `gem install my-gem` (transitive URI deps, plugin NOT pre-installed) | N/A — plugin not loaded | ❌ |

The Bundler path works because Bundler uses **only** the Compact Index
(`versions` + `info/`) for resolution and has its own gem download mechanism.
The `gem install` path fails because RubyGems' native resolver also requires
the legacy `quick/Marshal.4.8/` endpoint for spec fetching and
`gems/` for `.gem` file downloads — both under the namespace path.

---

## Separate issue: `gem.coop` (production) returns HTTP 200 with body `"404"`

The production server at `gem.coop` (not `beta.gem.coop`) returns **HTTP 200**
with a plain-text body of `"404"` for namespace endpoints:

```
GET https://gem.coop/@kaspth/versions     → 200, body: "404"
GET https://gem.coop/@kaspth/info/oaken   → 200, body: "404"
```

This is problematic because RubyGems interprets an HTTP 200 response as a
successful Compact Index reply. It creates an `APISet` and attempts to parse
the string `"404"` as version data, leading to confusing downstream failures.

These should return a proper **HTTP 404** status code so that RubyGems raises
`Gem::RemoteFetcher::FetchError` and falls back gracefully.

---

## Environment

- Ruby 4.0.1
- RubyGems 4.0.5+
- `namespaced-gem` (development, HEAD)
- Tested: 2026-03-07
