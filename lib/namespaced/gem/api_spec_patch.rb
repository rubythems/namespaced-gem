# frozen_string_literal: true

require_relative "namespace_source_registry"

module Namespaced
  module Gem
    # Patches Gem::Resolver::APISpecification#spec to synthesize a minimal
    # Gem::Specification from the Compact Index data that the APISpecification
    # already holds — instead of hitting the legacy Marshal endpoint
    # (quick/Marshal.4.8/…) which namespace servers don't serve.
    #
    # Background:
    #   When RubyGems resolves a gem, the APISet fetches version/dependency
    #   data from the Compact Index (info/{gem}) and stores it in the
    #   APISpecification.  But when add_always_install or the install pipeline
    #   calls APISpecification#spec, it tries to fetch a full Gem::Specification
    #   via source.fetch_spec — which hits the Marshal endpoint and fails with
    #   Zlib::DataError (the server returns HTML 404, not deflated Marshal data).
    #
    # This patch:
    #   For namespace sources (identified via NamespaceSourceRegistry), builds a
    #   Gem::Specification from the fields already present on the APISpecification
    #   (name, version, platform, dependencies, required_ruby_version,
    #   required_rubygems_version).  This is sufficient for resolution and for
    #   the install pipeline to proceed to the download phase.  The actual .gem
    #   file contains a full embedded gemspec that takes over during installation.
    #
    # Also patches #fetch_development_dependencies for the same reason — it also
    # calls source.fetch_spec internally.
    module ApiSpecPatch
      def self.apply!
        return if ::Gem::Resolver::APISpecification.instance_variable_get(:@namespaced_gem_api_spec_patched)

        ::Gem::Resolver::APISpecification.prepend(SpecPatch)
        ::Gem::Resolver::APISpecification.instance_variable_set(:@namespaced_gem_api_spec_patched, true)
      end

      module SpecPatch
        # Override #spec to synthesize a Gem::Specification for namespace sources
        # instead of fetching from the Marshal endpoint.
        def spec
          if NamespaceSourceRegistry.namespace_source?(source)
            @spec ||= _build_namespace_spec
          else
            super
          end
        end

        # Override #fetch_development_dependencies to avoid hitting the Marshal
        # endpoint for namespace sources.  For namespace sources we simply
        # keep the dependencies already parsed from the Compact Index — dev
        # deps are not available from the Compact Index anyway.
        def fetch_development_dependencies
          if NamespaceSourceRegistry.namespace_source?(source)
            # No-op: Compact Index doesn't distinguish dev deps.
            # The full gemspec inside the .gem file will have them.
            nil
          else
            super
          end
        end

        private

        # Build a minimal Gem::Specification from the Compact Index data
        # already parsed into this APISpecification's instance variables.
        #
        # Fields populated:
        #   - name, version, platform         (from Compact Index)
        #   - dependencies                    (from Compact Index)
        #   - required_ruby_version           (from Compact Index, if present)
        #   - required_rubygems_version       (from Compact Index, if present)
        #
        # Fields NOT available from Compact Index (filled by the .gem file):
        #   - summary, description, authors, email, homepage, license
        #   - executables, extensions, metadata, post_install_message
        #   - files, require_paths, etc.
        def _build_namespace_spec
          s = ::Gem::Specification.new
          s.name     = @name
          s.version  = @version
          s.platform = @platform

          # Rebuild dependencies.  @dependencies holds Gem::Dependency objects
          # (frozen) parsed from the Compact Index info/ response.
          @dependencies.each do |dep|
            s.add_runtime_dependency(dep.name, *dep.requirement.as_list)
          end

          s.required_ruby_version     = ::Gem::Requirement.new(*@required_ruby_version.as_list)     if @required_ruby_version
          s.required_rubygems_version  = ::Gem::Requirement.new(*@required_rubygems_version.as_list) if @required_rubygems_version

          # Minimal required_paths so Gem::Specification validation doesn't
          # complain.  The real value comes from the .gem file.
          s.require_paths = ["lib"]

          # Mark authors to avoid Specification validation warnings.
          s.authors = ["(namespace source — full metadata in .gem file)"]
          s.summary = "(resolved from namespace source #{source.uri})"

          s
        end
      end
    end
  end
end
