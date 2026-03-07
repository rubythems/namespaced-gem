# frozen_string_literal: true

require_relative "gem/version"
require_relative "gem/uri_dependency"
require_relative "gem/namespace_source_registry"
require_relative "gem/dependency_patch"
require_relative "gem/api_spec_patch"
require_relative "gem/download_patch"
require_relative "gem/bundler_integration"
require_relative "gem/bundler_resolver_patch"
require_relative "gem/gem_resolver_patch"

module Namespaced
  # Namespaced::Gem is a RubyGems plugin/shim that enables gemspec dependencies
  # to be declared as full URIs, pointing to namespaced gem sources such as
  # gem.coop namespaces (e.g. https://beta.gem.coop/@myspace/my-gem).
  #
  # When installed, this gem's rubygems_plugin.rb is loaded at RubyGems boot,
  # patching Gem::Dependency to accept URI names, Bundler::Dsl to automatically
  # inject source blocks, and both Bundler's and RubyGems' resolvers to remap
  # URI-named transitive deps to their real names and namespace sources.
  module Gem
    class Error < StandardError; end
  end
end
