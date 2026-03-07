# Hookah::Gem

Investigation into RubyGems plugin hot-loading — specifically whether a
`rubygems_plugin.rb` carried by a **previously-uninstalled dependency gem** can
be live-loaded into the running `gem install` process.

**TL;DR — Yes, it works, via `Gem::Installer#load_plugin`.**

---

## How RubyGems Loads Plugins

### Path 1 — at `gem` startup (already-installed gems only)

`GemRunner#run` calls two methods before executing any command:

```ruby
Gem.load_env_plugins   # scans $LOAD_PATH for rubygems_plugin.rb
Gem.load_plugins       # scans $GEM_HOME/plugins/ for *_plugin.rb stubs
```

These only reach gems that are **already on disk**.

### Path 2 — hot-load during `gem install` (the interesting one)

`Gem::Installer#install` runs this sequence for **every gem** it installs:

```
pre_install_checks
run_pre_install_hooks        ← Gem.pre_install hooks fire here
extract_files
build_extensions
run_post_build_hooks         ← Gem.post_build hooks fire here
generate_plugins             ← writes $GEM_HOME/plugins/<name>_plugin.rb stub
write_spec
load_plugin                  ← HOT-LOADS the plugin into the running process
run_post_install_hooks       ← Gem.post_install hooks fire here
```

`load_plugin` (installer.rb ~line 986):

```ruby
def load_plugin
  specs = Gem::Specification.find_all_by_name(spec.name)
  # Only hot-load on first install — avoids loading two versions at once.
  return unless specs.size == 1

  plugin_files = spec.plugins.map do |plugin|
    File.join(@plugins_dir, "#{spec.name}_plugin#{File.extname(plugin)}")
  end
  Gem.load_plugin_files(plugin_files)
end
```

`spec.plugins` (basic_specification.rb) discovers files via:

```ruby
def plugins
  matches_for_glob("rubygems#{Gem.plugin_suffix_pattern}")
  # expands to lib/rubygems_plugin{,.rb,.so,...}
end
```

So any gem with `lib/rubygems_plugin.rb` in its `require_paths` is a plugin gem.

---

## The Dependency Hot-Load Trick

`RequestSet#install` (request_set.rb) installs gems in **topological order**
(`sorted_requests` uses `TSort` / `strongly_connected_components`):
dependencies are installed **before** the gems that require them.

This creates the following opportunity:

```
gem install hookah-gem
  │
  ├─ 1. Resolve graph: hookah-gem → hookah-core (has rubygems_plugin.rb)
  │
  ├─ 2. Install hookah-core first (leaf node)
  │      └─ Gem::Installer#load_plugin fires
  │           └─ hookah-core's rubygems_plugin.rb is require'd into THIS process
  │                └─ Gem.pre_install / post_install / done_installing hooks register
  │
  └─ 3. Install hookah-gem
         └─ run_pre_install_hooks  ← hooks from hookah-core are already active!
         └─ run_post_install_hooks ← same
```

To use this pattern, add the plugin-carrying gem as a runtime dependency:

```ruby
# hookah-gem.gemspec
spec.add_dependency "hookah-core"   # hookah-core ships lib/rubygems_plugin.rb
```

### Critical caveat

The hot-load only fires when `Gem::Specification.find_all_by_name(spec.name).size == 1`,
i.e. **this is the very first version of the dependency on the system**.  If the
user already has any version of `hookah-core` installed the plugin stub is
regenerated but the file is **not** `require`'d into the live process.  The
next time the `gem` command runs (a fresh process) `Gem.load_plugins` will pick
it up from the stubs directory.

---

## Available Hooks (registered inside `lib/rubygems_plugin.rb`)

| Hook | Fires | Abort? |
|------|-------|--------|
| `Gem.pre_install { \|installer\| }` | Before files are extracted | `return false` raises `Gem::InstallError` |
| `Gem.post_build { \|installer\| }` | After native exts compile | `return false` removes gem dir + raises |
| `Gem.post_install { \|installer\| }` | After gem fully installed | No |
| `Gem.done_installing { \|dep_installer, specs\| }` | After entire batch done | No |

`installer` is a `Gem::Installer`; `installer.spec` is the `Gem::Specification`
being installed.  `dep_installer` is the `Gem::DependencyInstaller` that drove
the whole `gem install` run.

See `lib/rubygems_plugin.rb` in this repo for an annotated skeleton.

## Installation

TODO: Replace `UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG` with your gem name right after releasing it to RubyGems.org. Please do not do it earlier due to security reasons. Alternatively, replace this section with instructions to install your gem from git if you don't plan to release to RubyGems.org.

Install the gem and add to the application's Gemfile by executing:

```bash
bundle add UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

If bundler is not being used to manage dependencies, install the gem by executing:

```bash
gem install UPDATE_WITH_YOUR_GEM_NAME_IMMEDIATELY_AFTER_RELEASE_TO_RUBYGEMS_ORG
```

## Usage

TODO: Write usage instructions here

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/hookah-gem. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/[USERNAME]/hookah-gem/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Hookah::Gem project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/[USERNAME]/hookah-gem/blob/main/CODE_OF_CONDUCT.md).
