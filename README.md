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
      uri_dependency.rb           # URI parser (value object)
      dependency_patch.rb         # Gem::Dependency patch (helper methods)
      bundler_integration.rb      # Bundler::Dsl#gemspec patch
      bundler_resolver_patch.rb   # Bundler::Definition / Resolver transitive dep handling
      gem_resolver_patch.rb       # Gem::RequestSet / InstallerSet for `gem install`
```

---

## Known Limitations

1. **Plugin must be installed as a gem.** This gem works as a RubyGems plugin
   (`rubygems_plugin.rb`), which means it must be *installed* — not just listed
   in a Gemfile — so that RubyGems loads the plugin at boot before any gemspec
   is evaluated. In Ruby 4.0+, RubyGems auto-loads `bundler/setup` when it
   detects a Gemfile in the working directory, and this happens *before*
   `RUBYOPT` `-r` flags are processed. The plugin must already be in the gem
   path to intercept in time.

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
