# namespaced-gem

A RubyGems plugin that enables gemspec dependencies to be declared as
full URIs, pointing to **namespaced gem sources** such as
[gem.coop namespaces](https://gem.coop/updates/5/).

This implements the ideas discussed in
[gem-coop/gem.coop#12](https://github.com/gem-coop/gem.coop/issues/12).

---

## The Problem

gem.coop's public beta introduced _namespaces_ — isolated gem registries per
user or organization:

```
https://beta.gem.coop/@myspace          # namespace index
https://beta.gem.coop/@myspace/my-gem   # canonical gem URI
```

Today, gemspecs declare dependencies as plain names:

```ruby
spec.add_dependency "rack", "~> 3.0"
```

There is no standard way to express _which gem server_ (and _which namespace_)
a dependency comes from inside the gemspec itself. The user must manually add
a `source` block to their Gemfile — which defeats the purpose of publishing a
self-describing gemspec.

The question this prototype asks: **can a gemspec declare its own source for a
dependency, using the dependency name string alone?**

```ruby
spec.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
```

---

## Key Finding: RubyGems 4.0.5+ Happens to Allow URI Names

RubyGems 4.0.5 removed the old `Gem::Dependency::VALID_NAME_PATTERN`
restriction entirely — any String is now accepted as a dependency name:

```ruby
dep = Gem::Dependency.new("https://beta.gem.coop/@ns/foo", "~> 1.0")
dep.name  # => "https://beta.gem.coop/@ns/foo"
```

However, **RubyGems has no idea what to do with a URI-named dependency.** It
will happily store the string, but `gem install` will try to look up that
literal name on rubygems.org — and fail. Neither RubyGems nor Bundler knows
how to extract the real gem name, derive the namespace source URL, or resolve
transitive dependencies that use URI names.

**This gem bridges that gap.** It teaches both RubyGems' resolver (`gem
install`) and Bundler's resolver (`bundle install`) how to parse URI dependency
names, route them to the correct namespace source, and remap transitive deps
on the fly.

---

## How It Works

This gem ships a `rubygems_plugin.rb` that is automatically loaded by RubyGems
at boot — before any gemspec is parsed.

### 1. `Gem::Dependency` patch (`DependencyPatch`)

Prepends helper methods `#uri_gem?` and `#uri_dependency` onto
`Gem::Dependency`.

```ruby
dep = Gem::Dependency.new("https://beta.gem.coop/@myspace/my-gem", "~> 1.0")
dep.uri_gem?          # => true
dep.uri_dependency    # => #<Namespaced::Gem::UriDependency gem_name="my-gem" source_url="https://beta.gem.coop/@myspace">
```

### 2. URI parser (`UriDependency`)

Parses a URI dependency name into its components:

| Part          | Example                            |
|---------------|------------------------------------|
| `server_base` | `https://beta.gem.coop`            |
| `namespace`   | `@myspace`                         |
| `gem_name`    | `my-gem`                           |
| `source_url`  | `https://beta.gem.coop/@myspace`   |

Supports two forms:
- **Full URI**: `https://beta.gem.coop/@myspace/my-gem`
- **Shorthand**: `@myspace/my-gem` (defaults to `https://gem.coop`)

### 3. Bundler DSL integration (`BundlerIntegration`)

Patches `Bundler::Dsl#gemspec` so that after standard gemspec processing, any
URI-named runtime dependencies automatically inject a `source` block:

```ruby
# What the user writes in their Gemfile:
gemspec

# What this patch injects automatically for URI deps:
# source "https://beta.gem.coop/@myspace" do
#   gem "my-gem", "~> 1.0"
# end
```

This means the Gemfile needs **no manual source declarations** for URI deps
found in the gemspec.

---

## Usage

There are three ways to use `namespaced-gem`, depending on your situation.

### Use Case 1: Gem authors (primary)

Add `namespaced-gem` as a runtime dependency of your gem. It is published on
rubygems.org and acts as a bridge to gem.coop namespaces.

```ruby
Gem::Specification.new do |spec|
  spec.name    = "my-gem"
  spec.version = "1.0.0"

  # This gem must be a runtime dependency so that its rubygems_plugin.rb
  # is installed and loaded by RubyGems at boot — before any gemspec
  # containing URI dependencies is evaluated.
  spec.add_dependency "namespaced-gem"

  # Traditional dependency from RubyGems.org:
  spec.add_dependency "rack", "~> 3.0"

  # Namespaced dependency from gem.coop (full URI):
  spec.add_dependency "https://beta.gem.coop/@myspace/special-gem", "~> 0.5"

  # Shorthand (defaults to gem.coop):
  spec.add_dependency "@myorg/internal-tool", ">= 2.0"
end
```

When a user runs `gem install my-gem`, RubyGems installs `namespaced-gem` as
a transitive dependency. On the next RubyGems boot the plugin is in the gem
path and is loaded automatically — URI-named dependencies are then parsed,
routed to the correct namespace source, and resolved transparently.

No changes to the downstream user's Gemfile are required. If they use Bundler,
their Gemfile can remain:

```ruby
source "https://rubygems.org"
gemspec
```

The Bundler integration automatically injects the correct `source` blocks for
any URI dependencies found in the gemspec.

### Use Case 2: Application developers

If you are not publishing a gem but want to use URI-style dependencies in an
application, install `namespaced-gem` directly:

```bash
gem install namespaced-gem
```

Because `rubygems_plugin.rb` files are only loaded from **installed** gems, the
gem must be present in the gem path _before_ RubyGems evaluates any gemspec
that contains URI dependencies. In practice this means:

1. Install the gem first: `gem install namespaced-gem`
2. Then declare URI dependencies in your gemspec or Gemfile as usual.

> **Note:** Simply listing `gem "namespaced-gem"` in a Gemfile is _not
> sufficient_ on its own — Bundler evaluates the Gemfile (and its `gemspec`
> directive) before it installs gems, so the plugin would not yet be loaded.
> The gem must already be installed via `gem install` (or as a transitive
> dependency of another installed gem, as in Use Case 1).

### Use Case 3: Global installation (enable namespace support Ruby-wide)

Install `namespaced-gem` once into your Ruby environment and every subsequent
`gem install` and `bundle install` in that Ruby will be able to resolve
URI-named dependencies — no per-project configuration needed.

```bash
gem install namespaced-gem
```

That's it. The `rubygems_plugin.rb` is now in the gem path and will be loaded
by RubyGems on every boot. From this point forward:

- `gem install some-gem` will automatically resolve any URI-named transitive
  dependencies found in `some-gem`'s gemspec.
- `bundle install` in any project will automatically inject the correct
  `source` blocks for URI dependencies found in gemspecs.

This is useful for CI images, Docker containers, or development machines where
you want namespace support available globally without requiring each gem or
project to explicitly depend on `namespaced-gem`.

```dockerfile
# Example: Dockerfile
RUN gem install namespaced-gem
# All subsequent gem/bundle commands in this image now support URI deps.
```

```bash
# Example: CI setup step
gem install namespaced-gem
bundle install   # URI deps in any gemspec are resolved automatically
```

---

## Architecture

```
lib/
  rubygems_plugin.rb              # Loaded by RubyGems at boot
  namespaced/
    gem.rb                        # Main module
    gem/
      version.rb
      uri_dependency.rb           # URI parser (value object)
      dependency_patch.rb         # Gem::Dependency patch (helper methods)
      bundler_integration.rb      # Bundler::Dsl#gemspec patch
      bundler_resolver_patch.rb   # Bundler::Definition / Resolver transitive dep handling
      gem_resolver_patch.rb       # Gem::RequestSet / InstallerSet for `gem install`
```

---

## Known Limitations

1. **Plugin must be installed before first use (application developers only).**
   This gem works as a RubyGems plugin (`rubygems_plugin.rb`), which means it
   must be _installed_ in the gem path so that RubyGems loads the plugin at
   boot before any gemspec containing URI dependencies is evaluated. For gem
   authors (Use Case 1), this happens automatically — when a user installs your
   gem, `namespaced-gem` is installed as a transitive dependency and available
   on the next boot. For global installations (Use Case 3), the plugin is
   already in the gem path by definition. For application developers
   (Use Case 2), the gem must be installed explicitly with
   `gem install namespaced-gem` before running `bundle install`, because
   Bundler evaluates the Gemfile before it installs gems. In Ruby 4.0+,
   RubyGems auto-loads `bundler/setup` when it detects a Gemfile in the working
   directory, and this happens _before_ `RUBYOPT` `-r` flags are processed —
   so the plugin must already be in the gem path.

2. **Gemspec linting:** Tools that validate gemspecs (e.g. `gem build`, `rake
   release`) work fine because `SpecificationPolicy#validate_name` only
   validates the gem's *own* name — it does not check dependency names.

---

## Version Constraints

Version requirements work exactly as they always have — they are the second
argument to `add_dependency`, completely separate from the name:

```ruby
spec.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
#                    ^^^^^^^^^^ URI name ^^^^^^^^^^^^^^^^^^   ^^^^^^^^
#                                                             version
```

All standard operators (`~>`, `>=`, `=`, etc.) are supported unchanged.

---

## Development

```bash
bundle install
bundle exec rspec              # unit + offline integration tests
bundle exec rspec --tag network  # network integration tests (hits beta.gem.coop)
bundle exec rake               # tests + rubocop
```

The network integration tests resolve a real gem (`@kaspth/oaken`) from
`beta.gem.coop` and verify `bundle lock` produces a correct `Gemfile.lock`.
They are excluded from the default `rspec` run and must be opted into with
`--tag network`.

---

## Contributing

Bug reports and pull requests are welcome on GitLab at
<https://gitlab.com/galtzo-floss/namespaced-gem>.

This project is intended to be a safe, welcoming space for collaboration, and
contributors are expected to adhere to the
[code of conduct](https://gitlab.com/galtzo-floss/namespaced-gem/-/blob/main/CODE_OF_CONDUCT.md).

## Code of Conduct

Everyone interacting in the namespaced-gem project's codebases, issue trackers,
chat rooms and mailing lists is expected to follow the
[code of conduct](https://gitlab.com/galtzo-floss/namespaced-gem/-/blob/main/CODE_OF_CONDUCT.md).
