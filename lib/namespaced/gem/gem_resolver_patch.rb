# frozen_string_literal: true

require_relative "uri_dependency"
require_relative "namespace_source_registry"

module Namespaced
  module Gem
    # Patches Gem::RequestSet#resolve to handle URI-named deps during
    # `gem install` (which uses RubyGems' own resolver, not Bundler).
    #
    # When `gem install orig-foo` resolves orig-foo's transitive dependencies
    # and encounters a dep named "https://beta.gem.coop/@pboling/foo", it would
    # normally query rubygems.org for a gem with that literal name — and fail.
    #
    # This patch intercepts Gem::RequestSet#resolve. Before resolution starts,
    # it scans @dependencies for URI-named deps. For each one it:
    #   1. Creates a Gem::Source for the namespace URL.
    #   2. Derives the resolver set for that source (via Bundler-compatible API).
    #   3. Adds that set to @sets so the resolver can find specs there.
    #   4. Replaces the URI dep with a plain Gem::Dependency for the real name.
    #
    # Transitive URI deps (discovered when inspecting the fetched gemspec of a
    # transitively-resolved gem) are handled by patching
    # Gem::Resolver::InstallerSet#find_all to intercept and remap them on the
    # fly while the recursive resolution walk runs.
    module GemResolverPatch
      def self.apply!
        return if ::Gem::RequestSet.instance_variable_get(:@namespaced_gem_patched)

        ::Gem::RequestSet.prepend(RequestSetPatch)
        ::Gem::Resolver::InstallerSet.prepend(InstallerSetPatch)
        ::Gem::RequestSet.instance_variable_set(:@namespaced_gem_patched, true)
      end

      # Patched into Gem::RequestSet to remap URI deps before resolution.
      module RequestSetPatch
        def resolve(set = ::Gem::Resolver::BestSet.new)
          uri_sets = {}

          @dependencies = @dependencies.map do |dep|
            next dep unless Namespaced::Gem::UriDependency.uri?(dep.name)

            uri_dep = Namespaced::Gem::UriDependency.parse(dep.name)

            # Create a Gem::Source for the namespace URL and derive its
            # resolver set (APISet if the server supports compact index, else
            # IndexSet).  Cache per source_url to avoid duplicate queries.
            unless uri_sets.key?(uri_dep.source_url)
              begin
                src = ::Gem::Source.new(uri_dep.source_url)
                Namespaced::Gem::NamespaceSourceRegistry.register(uri_dep.source_url)
                uri_sets[uri_dep.source_url] = src.dependency_resolver_set
              rescue StandardError => e
                raise Namespaced::Gem::Error,
                      "Failed to create resolver set for #{uri_dep.source_url.inspect}: #{e.message}"
              end
            end

            ::Gem::Dependency.new(uri_dep.gem_name, dep.requirement, dep.type)
          end

          # Add the namespace resolver sets before the standard set.
          uri_sets.each_value { |uri_set| @sets.unshift(uri_set) }

          super(set)
        end
      end

      # Patched into Gem::Resolver::InstallerSet to remap URI-named transitive
      # deps encountered while the resolver walks the dependency graph.
      #
      # When the resolver fetches the spec for a just-resolved gem and finds
      # its own URI-named deps, it calls find_all with a Gem::Resolver::DependencyRequest
      # whose name is the URI string.  We intercept that call, remap to the
      # real name, create the right source if needed, and return matching specs.
      module InstallerSetPatch
        def find_all(req)
          return super unless Namespaced::Gem::UriDependency.uri?(req.name)

          uri_dep = Namespaced::Gem::UriDependency.parse(req.name)

          resolver_set = _namespaced_resolver_set(uri_dep.source_url)

          # Build a remapped request with the real gem name.
          remapped_dep = ::Gem::Dependency.new(uri_dep.gem_name, req.dependency.requirement, req.dependency.type)
          remapped_req = ::Gem::Resolver::DependencyRequest.new(remapped_dep, req.requester)

          resolver_set.find_all(remapped_req)
        rescue StandardError => e
          raise Namespaced::Gem::Error,
                "Failed to resolve URI dependency #{req.name.inspect}: #{e.message}"
        end

        private

        # Cache resolver sets per source URL to avoid repeated network lookups.
        def _namespaced_resolver_set(source_url)
          @_namespaced_resolver_sets ||= {}
          @_namespaced_resolver_sets[source_url] ||= begin
            src = ::Gem::Source.new(source_url)
            Namespaced::Gem::NamespaceSourceRegistry.register(source_url)
            src.dependency_resolver_set
          end
        end
      end
    end
  end
end
