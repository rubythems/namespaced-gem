# frozen_string_literal: true

module Namespaced
  module Gem
    # Thread-safe registry of namespace source URLs.
    #
    # When the GemResolverPatch or other code creates a Gem::Source for a
    # namespace URL (e.g. "https://beta.gem.coop/@kaspth"), it registers
    # that URL here.  Later, patches like ApiSpecPatch and DownloadPatch
    # can check whether a given Gem::Source is a namespace source — without
    # relying on heuristics like scanning the URL for "@" segments.
    #
    # This registry is the single source of truth for "is this source a
    # namespace source that our plugin manages?"
    module NamespaceSourceRegistry
      @mutex = Mutex.new
      @sources = {} # normalized_url_string => true

      # Register a namespace source URL.  Safe to call multiple times with
      # the same URL (idempotent).
      def self.register(source_url)
        normalized = normalize(source_url)
        @mutex.synchronize { @sources[normalized] = true }
      end

      # Returns true if +source+ is a Gem::Source whose URI was previously
      # registered as a namespace source.
      def self.namespace_source?(source)
        return false unless source.is_a?(::Gem::Source)

        uri = source.respond_to?(:uri) && source.uri
        return false unless uri

        namespace_source_url?(uri)
      end

      # Returns true if the given URL string (or URI object) was registered.
      def self.namespace_source_url?(url)
        normalized = normalize(url)
        @mutex.synchronize { @sources.key?(normalized) }
      end

      # Clear all registered sources.  Primarily for testing.
      def self.clear!
        @mutex.synchronize { @sources.clear }
      end

      # Returns a frozen copy of all registered source URLs (for debugging).
      def self.registered_urls
        @mutex.synchronize { @sources.keys.freeze }
      end

      class << self
        private

        def normalize(url)
          url.to_s.chomp("/")
        end
      end
    end
  end
end
