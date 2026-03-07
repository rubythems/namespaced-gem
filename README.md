# namespaced-gem

A RubyGems plugin prototype that enables gemspec dependencies to be declared as
full URIs, pointing to **namespaced gem sources** such as
[gem.coop namespaces](https://gem.coop/updates/5/).

This is a feasibility exploration of the ideas discussed in
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

## Key Finding: RubyGems 4.0.5+ Already Accepts URI Names

When we set out to write this prototype, we expected to need to widen the
`Gem::Dependency::VALID_NAME_PATTERN` regex. However, **RubyGems 4.0.5 removed
the name pattern restriction entirely** — any String is now a valid dependency
name:

```ruby
dep = Gem::Dependency.new("https://beta.gem.coop/@ns/foo", "~> 1.0")
dep.name  # => "https://beta.gem.coop/@ns/foo"
```

This means **the gemspec side is already feasible** on modern Ruby. The
remaining challenge is the **Bundler resolution side**: Bundler needs to know
which source server to use when resolving a URI-named dependency.

For older RubyGems (< 4.0.5), this gem provides a backward-compatible patch
that widens `VALID_NAME_PATTERN` to also permit URIs.

---

## How It Works

This gem ships a `rubygems_plugin.rb` that is automatically loaded by RubyGems
at boot — before any gemspec is parsed.

### 1. `Gem::Dependency` patch (`DependencyPatch`)

- On older RubyGems: widens `VALID_NAME_PATTERN` to allow URI characters.
- On all versions: prepends helper methods `#uri_gem?` and `#uri_dependency`
  onto `Gem::Dependency`.

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

### 1. Install this gem

```bash
gem install namespaced-gem
```

Or add it to your project's `Gemfile`:

```ruby
gem "namespaced-gem"
```

### 2. Declare URI dependencies in your gemspec

```ruby
Gem::Specification.new do |spec|
  spec.name    = "my-project"
  spec.version = "1.0.0"

  # Traditional dependency from RubyGems.org:
  spec.add_dependency "rack", "~> 3.0"

  # Namespaced dependency from gem.coop:
  spec.add_dependency "https://beta.gem.coop/@myspace/special-gem", "~> 0.5"

  # Shorthand (defaults to gem.coop):
  spec.add_dependency "@myorg/internal-tool", ">= 2.0"
end
```

### 3. Your Gemfile stays simple

```ruby
source "https://rubygems.org"
gemspec
```

The Bundler integration automatically resolves URI deps to their correct
namespaced source.

---

## Architecture

```
lib/
  rubygems_plugin.rb              # Loaded by RubyGems at boot
  namespaced/
    gem.rb                        # Main module
    gem/
      version.rb
      uri_dependency.rb           # URI parser
      dependency_patch.rb         # Gem::Dependency patch (helper methods + old RubyGems compat)
      bundler_integration.rb      # Bundler::Dsl#gemspec patch
```

---

## Known Limitations & Open Questions

1. **Ordering constraint**: The plugin must be *installed* (not just in Gemfile)
   for the patch to fire before Bundler reads the gemspec. If this gem is only
   listed in the Gemfile, RubyGems loads the plugin at Bundler boot which may
   still be early enough — but this needs more testing.

2. **Lock file**: URI-sourced deps will appear as remote sources in
   `Gemfile.lock`. This may require Bundler to be aware of the source. Initial
   testing suggests it works correctly since we inject proper `source` blocks.

3. **Gemspec linting**: Tools that validate gemspecs (e.g. `gem build`, `rake
   release`) should work fine on RubyGems ≥ 4.0.5. On older RubyGems, the
   `SpecificationPolicy#validate_name` only validates the gem's *own* name
   (not its dependencies), so URI deps won't trigger that check.

4. **Version constraints**: Version requirements work as normal since they are
   the second argument to `add_dependency`, separate from the name.

5. **Upstream path**: The cleanest solution would be Bundler/RubyGems natively
   supporting a `source:` keyword in `add_dependency`. This prototype
   demonstrates the feasibility of a shim while that support is being developed.

---

## Development

```bash
bundle install
bundle exec rake spec    # run tests
bundle exec rake         # tests + rubocop
```

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

