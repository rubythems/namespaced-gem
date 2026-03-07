# frozen_string_literal: true

require "rubygems/dependency"
require_relative "uri_dependency"

module Namespaced
  module Gem
    # Patches Gem::Dependency to support URI-style gem names and expose helper
    # methods for working with them.
    #
    # RubyGems >= 4.0.5 already accepts any String as a dependency name (the
    # old VALID_NAME_PATTERN restriction was removed), so no name-validation
    # overrides are necessary.  This patch simply adds:
    #
    #   #uri_gem?          — true if the dependency name is a URI
    #   #uri_dependency    — returns a parsed Namespaced::Gem::UriDependency or nil
    module DependencyPatch
      def self.apply!
        return if ::Gem::Dependency.instance_variable_get(:@namespaced_gem_patched)

        ::Gem::Dependency.prepend(InstanceMethods)

        # Set the guard only after all patches succeed.
        ::Gem::Dependency.instance_variable_set(:@namespaced_gem_patched, true)
      end

      module InstanceMethods
        # Returns true if this dependency was declared as a URI.
        def uri_gem?
          Namespaced::Gem::UriDependency.uri?(name)
        end

        # Returns a parsed UriDependency for this dep, or nil if not a URI dep.
        def uri_dependency
          return @uri_dependency if defined?(@uri_dependency)

          @uri_dependency = uri_gem? ? Namespaced::Gem::UriDependency.parse(name) : nil
        end
      end
    end
  end
end
