# frozen_string_literal: true

require "uri"

module Namespaced
  module Gem
    # Represents a gem dependency specified as a URI, enabling namespaced gem
    # sources (e.g. gem.coop namespaces) to be declared directly in gemspecs.
    #
    # Supported URI formats:
    #   Full URI:   "https://beta.gem.coop/@myspace/my-gem"
    #   Shorthand:  "@myspace/my-gem"  (defaults to https://gem.coop)
    #
    # Usage in a gemspec:
    #   spec.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
    class UriDependency
      DEFAULT_SERVER = "https://gem.coop"

      # Pattern matching full HTTPS/HTTP URIs to a namespaced gem.
      # e.g. https://beta.gem.coop/@namespace/gem-name
      FULL_URI_PATTERN = %r{
        \A
        (https?://[^/]+)    # server base, e.g. https://beta.gem.coop
        /
        (@[^/]+)            # namespace, e.g. @myspace
        /
        ([a-zA-Z0-9_\-]+)  # gem name
        \z
      }x

      # Shorthand: @namespace/gem-name (no server; defaults to gem.coop)
      SHORTHAND_PATTERN = %r{
        \A
        (@[^/]+)            # namespace, e.g. @myspace
        /
        ([a-zA-Z0-9_\-]+)  # gem name
        \z
      }x

      attr_reader :original, :server_base, :namespace, :gem_name

      # Returns true if +name+ looks like a URI dependency.
      def self.uri?(name)
        return false unless name.is_a?(String)

        FULL_URI_PATTERN.match?(name) || SHORTHAND_PATTERN.match?(name)
      end

      # Parses +name+ into a UriDependency. Raises ArgumentError if not a URI dep.
      def self.parse(name)
        new(name)
      end

      def initialize(name)
        @original = name

        if (m = FULL_URI_PATTERN.match(name))
          @server_base = m[1]
          @namespace   = m[2]
          @gem_name    = m[3]
        elsif (m = SHORTHAND_PATTERN.match(name))
          @server_base = DEFAULT_SERVER
          @namespace   = m[1]
          @gem_name    = m[2]
        else
          raise ArgumentError, "Not a valid URI dependency: #{name.inspect}"
        end
      end

      # The Bundler source URL for this dependency's namespace.
      # This is what you'd put in a Gemfile `source` block.
      def source_url
        "#{server_base}/#{namespace}"
      end

      def to_s
        "#{source_url}/#{gem_name}"
      end

      def inspect
        "#<#{self.class} gem_name=#{gem_name.inspect} source_url=#{source_url.inspect}>"
      end
    end
  end
end
