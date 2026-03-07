# frozen_string_literal: true

# RubyGems plugin for namespaced-gem.
#
# This file is automatically loaded by RubyGems at boot time (before any
# gemspecs are evaluated) because it matches the `rubygems*_plugin.rb` naming
# convention in the gem's require path.
#
# What it does:
#   1. Patches Gem::Dependency to accept URI-style gem names such as
#      "https://beta.gem.coop/@namespace/gem-name".
#   2. Patches Gem::RequestSet and Gem::Resolver::InstallerSet so that
#      `gem install` can resolve URI-named deps against the correct namespace
#      source, both as direct deps and as transitive deps.
#   3. Patches Gem::Resolver::APISpecification#spec to synthesize a
#      Gem::Specification from Compact Index data for namespace sources —
#      bypassing the missing Marshal endpoint.
#   4. Patches Gem::Source#download to provide clear error messages when
#      namespace servers fail to serve .gem files.
#   5. Registers deferred patches for Bundler::Dsl, Bundler::Definition, and
#      Bundler::Resolver so that `bundle install` / `bundle add` automatically
#      resolve URI deps (both direct and transitive) against namespace sources.
#   6. Registers a Gem.done_installing hook that processes deferred namespace
#      dependencies stored in spec.metadata["namespaced_dependencies"]. This
#      enables the "hot-load" path: when namespaced-gem is installed as a leaf
#      dependency, Gem::Installer#load_plugin hot-loads this file, and the
#      done_installing hook triggers a second install pass for URI deps.
#
# See lib/namespaced/gem/dependency_patch.rb       — Gem::Dependency patch
#     lib/namespaced/gem/gem_resolver_patch.rb     — Gem::RequestSet / InstallerSet
#     lib/namespaced/gem/api_spec_patch.rb         — Gem::Resolver::APISpecification
#     lib/namespaced/gem/download_patch.rb         — Gem::Source#download
#     lib/namespaced/gem/bundler_integration.rb    — Bundler::Dsl patch
#     lib/namespaced/gem/bundler_resolver_patch.rb — Bundler::Definition / Resolver

require_relative "namespaced/gem/dependency_patch"
require_relative "namespaced/gem/gem_resolver_patch"
require_relative "namespaced/gem/api_spec_patch"
require_relative "namespaced/gem/download_patch"
require_relative "namespaced/gem/bundler_integration"
require_relative "namespaced/gem/bundler_resolver_patch"
require_relative "namespaced/gem/metadata_deps_hook"

# 1. Patch Gem::Dependency immediately — must run before any gemspec is parsed.
Namespaced::Gem::DependencyPatch.apply!

# 2. Patch Gem::RequestSet / InstallerSet for `gem install` — always available.
Namespaced::Gem::GemResolverPatch.apply!

# 3. Patch Gem::Resolver::APISpecification#spec to synthesize specs for
#    namespace sources (bypasses the missing Marshal endpoint).
Namespaced::Gem::ApiSpecPatch.apply!

# 4. Patch Gem::Source#download for clear namespace download error messages.
Namespaced::Gem::DownloadPatch.apply!

# 5. Patch Bundler if loaded, or defer until it is.
Namespaced::Gem::BundlerIntegration.apply_when_ready!
Namespaced::Gem::BundlerResolverPatch.apply_when_ready!

# 6. Register the done_installing hook for deferred namespace dependencies.
#
#    This enables the "hot-load" path for `gem install my-gem` where my-gem
#    depends on namespaced-gem and stores URI deps in metadata:
#
#      spec.metadata["namespaced_dependencies"] = "https://beta.gem.coop/@ns/foo ~> 1.0"
#
#    When namespaced-gem is installed as a leaf dependency (topological order),
#    Gem::Installer#load_plugin hot-loads this file into the running process.
#    The done_installing hook then fires after ALL gems in the batch finish
#    installing, reads the metadata, and triggers a second resolution pass
#    for the deferred namespace deps — with all patches now active.
Namespaced::Gem::MetadataDepsHook.register!
