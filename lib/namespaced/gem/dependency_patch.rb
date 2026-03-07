# frozen_string_literal: true

require "rubygems/dependency"
require_relative "uri_dependency"

module Namespaced
  module Gem
    # Patches Gem::Dependency to support URI-style gem names and expose helper
    # methods for working with them.
    #
    # In RubyGems >= 4.0.5, Gem::Dependency already accepts any String as a
    # dependency name (the old VALID_NAME_PATTERN restriction was removed).
    # In older RubyGems, the restriction exists and must be widened.
    #
    # Regardless of version, this patch adds:
    #   #uri_gem?          — true if the dependency name is a URI
    #   #uri_dependency    — returns a parsed Namespaced::Gem::UriDependency or nil
    module DependencyPatch
      # Pattern that replaces the old VALID_NAME_PATTERN for older RubyGems,
      # adding URI-format names to the allowed set.
      WIDENED_URI_PATTERN = /\A(?:[a-zA-Z0-9\.\-\_]+|https?:\/\/.+|@[^\/]+\/.+)\z/

      def self.apply!
        return if ::Gem::Dependency.instance_variable_get(:@namespaced_gem_patched)

        # For older RubyGems that restrict dependency names via VALID_NAME_PATTERN,
        # widen the pattern to also permit URI-style names.
        if ::Gem::Dependency.const_defined?(:VALID_NAME_PATTERN)
          ::Gem::Dependency.send(:remove_const, :VALID_NAME_PATTERN)
          ::Gem::Dependency.const_set(:VALID_NAME_PATTERN, WIDENED_URI_PATTERN)
        end

        ::Gem::Dependency.prepend(InstanceMethods)

        # For older RubyGems that have a validate_name private method, also
        # override it so URI names are validated via UriDependency rather than
        # the pattern check.
        if ::Gem::Dependency.private_method_defined?(:validate_name)
          ::Gem::Dependency.prepend(ValidateNameOverride)
        end

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

      # Only prepended on RubyGems versions that have validate_name.
      module ValidateNameOverride
        private

        def validate_name
          if uri_gem?
            # Validate the URI structure via UriDependency (raises ArgumentError if invalid).
            uri_dependency
          else
            super
          end
        end
      end
    end
  end
end

