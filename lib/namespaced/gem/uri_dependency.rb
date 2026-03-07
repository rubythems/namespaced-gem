# frozen_string_literal: true

require "uri"

module Namespaced
  module Gem
    # Represents a gem dependency specified as a URI, enabling namespaced gem
    # sources (e.g. gem.coop namespaces) to be declared directly in gemspecs.
    #
    # Supported formats:
    #   Full URI:   "https://beta.gem.coop/@myspace/my-gem"
    #   Shorthand:  "@myspace/my-gem"  (defaults to https://beta.gem.coop)
    #   Package URL (purl-spec):
    #     "pkg:gem/@myspace/my-gem"
    #     "pkg:gem/@myspace/my-gem?repository_url=https://beta.gem.coop"
    #     "pkg:gem/my-gem?repository_url=https://beta.gem.coop/@myspace"
    #
    # Usage in a gemspec:
    #   spec.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
    #   spec.add_dependency "pkg:gem/@myspace/my-gem", "~> 1.0"
    class UriDependency
      DEFAULT_SERVER = "https://beta.gem.coop"

      # Pattern matching full HTTPS/HTTP URIs to a namespaced gem.
      # e.g. https://beta.gem.coop/@namespace/gem-name
      FULL_URI_PATTERN = %r{
        \A
        (https?://[^/]+)      # server base, e.g. https://beta.gem.coop
        /
        (@[^/]+)              # namespace, e.g. @myspace
        /
        ([a-zA-Z0-9._\-]+)   # gem name (dots allowed per RubyGems convention)
        \z
      }x

      # Shorthand: @namespace/gem-name (no server; defaults to beta.gem.coop)
      SHORTHAND_PATTERN = %r{
        \A
        (@[^/]+)              # namespace, e.g. @myspace
        /
        ([a-zA-Z0-9._\-]+)   # gem name (dots allowed per RubyGems convention)
        \z
      }x

      # Package URL (purl-spec): pkg:gem/[@namespace/]gem-name[@version][?qualifiers]
      # See https://github.com/package-url/purl-spec
      #
      # Supported forms:
      #   pkg:gem/@myspace/my-gem                                       — namespace, default server
      #   pkg:gem/@myspace/my-gem?repository_url=https://beta.gem.coop  — namespace + explicit server
      #   pkg:gem/my-gem?repository_url=https://beta.gem.coop/@myspace  — namespace embedded in qualifier
      #
      # The @version component (if present) is captured but ignored — version
      # constraints come from the second argument to add_dependency.
      PURL_PATTERN = %r{
        \A
        pkg:gem/
        (?:(@[^/]+)/)?          # optional namespace, e.g. @myspace
        ([a-zA-Z0-9._\-]+)     # gem name
        (?:@[^?]+)?             # optional @version (ignored)
        (?:\?(.+))?             # optional ?qualifiers
        \z
      }x

      attr_reader :original, :server_base, :namespace, :gem_name

      # Returns true if +name+ looks like a URI dependency (full URI, shorthand,
      # or purl).
      def self.uri?(name)
        return false unless name.is_a?(String)

        FULL_URI_PATTERN.match?(name) || SHORTHAND_PATTERN.match?(name) || PURL_PATTERN.match?(name)
      end

      # Parses +name+ into a UriDependency. Raises ArgumentError if not a URI dep.
      def self.parse(name)
        new(name)
      end

      def initialize(name)
        @original = -String(name)

        if (m = FULL_URI_PATTERN.match(@original))
          @server_base = -m[1]
          @namespace   = -m[2]
          @gem_name    = -m[3]
        elsif (m = SHORTHAND_PATTERN.match(@original))
          @server_base = DEFAULT_SERVER
          @namespace   = -m[1]
          @gem_name    = -m[2]
        elsif (m = PURL_PATTERN.match(@original))
          parse_purl(m)
        else
          raise ArgumentError, "Not a valid URI dependency: #{name.inspect}"
        end

        freeze
      end

      # The Bundler source URL for this dependency's namespace.
      # This is what you'd put in a Gemfile `source` block.
      def source_url
        "#{server_base}/#{namespace}"
      end

      # Value equality — two UriDependency objects are equal when they refer
      # to the same gem in the same namespace on the same server.
      def ==(other)
        other.is_a?(self.class) &&
          server_base == other.server_base &&
          namespace == other.namespace &&
          gem_name == other.gem_name
      end

      alias eql? ==

      def hash
        [self.class, server_base, namespace, gem_name].hash
      end

      def to_s
        "#{source_url}/#{gem_name}"
      end

      def inspect
        "#<#{self.class} gem_name=#{gem_name.inspect} source_url=#{source_url.inspect}>"
      end

      private

      # Parse a purl match into server_base, namespace, and gem_name.
      #
      # Three forms:
      #   1. pkg:gem/@ns/name              → namespace from purl, default server
      #   2. pkg:gem/@ns/name?repository_url=https://server
      #                                    → namespace from purl, server from qualifier
      #   3. pkg:gem/name?repository_url=https://server/@ns
      #                                    → both from qualifier
      def parse_purl(match)
        purl_namespace = match[1]  # may be nil
        @gem_name      = -match[2]
        qualifiers     = parse_qualifiers(match[3])
        repo_url       = qualifiers["repository_url"]

        if purl_namespace
          # Forms 1 & 2: namespace is in the purl path
          @namespace   = -purl_namespace
          @server_base = repo_url ? -repo_url.chomp("/") : DEFAULT_SERVER
        elsif repo_url
          # Form 3: namespace is embedded in repository_url
          #   e.g. https://beta.gem.coop/@myspace
          repo_uri = URI.parse(repo_url)
          path_segments = repo_uri.path.split("/").reject(&:empty?)
          ns_segment = path_segments.find { |s| s.start_with?("@") }

          unless ns_segment
            raise ArgumentError,
                  "purl qualifier repository_url must include a @namespace or the purl path must: #{@original.inspect}"
          end

          @namespace   = -ns_segment
          @server_base = -"#{repo_uri.scheme}://#{repo_uri.host}#{repo_uri.port == repo_uri.default_port ? "" : ":#{repo_uri.port}"}"
        else
          raise ArgumentError,
                "purl for a namespaced gem must include a @namespace in the path or a repository_url qualifier: #{@original.inspect}"
        end
      end

      # Parse a URL query string into a Hash.  Returns an empty Hash for nil.
      def parse_qualifiers(raw)
        return {} unless raw

        URI.decode_www_form(raw).to_h
      end
    end
  end
end
