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
