# frozen_string_literal: true

require_relative "namespace_source_registry"

module Namespaced
  module Gem
    # Patches Gem::Source#download to provide clear, actionable error messages
    # when a namespace server fails to serve the .gem file.
    #
    # The namespace server is a discrete gem server and MUST serve all endpoints
    # — including /gems/{name}-{version}.gem — under its namespace path.  If it
    # does not, that is a server-side bug, NOT a reason to fall back to the root
    # server or any other source.
    #
    # CRITICAL INVARIANT:
    #   A namespaced gem (e.g. @kaspth/oaken) is a COMPLETELY DIFFERENT gem from
    #   a non-namespaced gem with the same base name (e.g. oaken on rubygems.org).
    #   The download MUST use the namespace source URL.  Stripping the namespace
    #   and downloading from the root server would risk fetching a completely
    #   different gem — a security and correctness violation.
    module DownloadPatch
      def self.apply!
        return if ::Gem::Source.instance_variable_get(:@namespaced_gem_download_patched)

        ::Gem::Source.prepend(SourceDownloadPatch)
        ::Gem::Source.instance_variable_set(:@namespaced_gem_download_patched, true)
      end

      module SourceDownloadPatch
        def download(spec, dir = Dir.pwd)
          super
        rescue ::Gem::RemoteFetcher::FetchError => e
          raise unless NamespaceSourceRegistry.namespace_source?(self)

          gem_file = "#{spec.full_name}.gem"
          expected_url = "#{uri}gems/#{gem_file}"

          raise Namespaced::Gem::Error,
                "Failed to download #{gem_file} from namespace source #{uri}\n" \
                "  Expected URL: #{expected_url}\n" \
                "  The namespace server must serve .gem files under its namespace path.\n" \
                "  This is a server-side requirement (see namespaced-gem ISSUE.md).\n" \
                "  The namespace CANNOT be stripped — @namespace/gem and gem are completely different gems.\n" \
                "  Original error: #{e.message}"
        end
      end
    end
  end
end
