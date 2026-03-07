# frozen_string_literal: true

require_relative "uri_dependency"

module Namespaced
  module Gem
    # Patches Bundler::Dsl to transparently handle URI-style gemspec dependencies.
    #
    # When a gemspec contains:
    #   spec.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
    #
    # And the consuming project's Gemfile has just:
    #   gemspec
    #
    # ...Bundler normally only sees the gem name as a path-source dependency and
    # resolves runtime deps lazily. URI-named deps would fail resolution because
    # no source lists a gem named "https://...".
    #
    # This integration patches Bundler::Dsl#gemspec so that after the standard
    # gemspec processing, it iterates the spec's runtime dependencies, detects
    # URI-style names, and injects the appropriate `source` blocks — exactly as
    # if the user had written:
    #
    #   source "https://beta.gem.coop/@myspace" do
    #     gem "my-gem", "~> 1.0"
    #   end
    #
    # This means the Gemfile requires no manual source declarations for URI deps.
    module BundlerIntegration
      @mutex = Mutex.new

      # Apply the patch to Bundler::Dsl. Safe to call multiple times (idempotent).
      def self.apply!
        return unless defined?(::Bundler::Dsl)
        return if ::Bundler::Dsl.instance_variable_get(:@namespaced_gem_patched)

        ::Bundler::Dsl.prepend(DslPatch)
        ::Bundler::Dsl.instance_variable_set(:@namespaced_gem_patched, true)
      end

      # Tries to apply the patch now; if Bundler isn't loaded yet, registers a
      # hook so the patch is applied the first time Bundler::Dsl is referenced.
      def self.apply_when_ready!
        if defined?(::Bundler::Dsl)
          apply!
        else
          @mutex.synchronize do
            # Re-check after acquiring lock (another thread may have set it up).
            return if @trace_installed

            # Bundler loads lazily in some contexts (e.g. plain `gem` commands).
            # We install a trace that fires on the first Bundler::Dsl class load.
            trace = TracePoint.new(:class) do |tp|
              dsl_loaded = begin
                tp.self == ::Bundler::Dsl
              rescue StandardError
                false
              end
              if dsl_loaded
                apply!
                trace.disable
              end
            end
            trace.enable
            @trace_installed = true
          end
        end
      end

      module DslPatch
        # Wraps the original Bundler::Dsl#gemspec to post-process URI dependencies.
        def gemspec(opts = nil)
          super

          # Find the gemspecs that were just registered.
          @gemspecs.each do |spec|
            inject_uri_sources_for(spec)
          end
        end

        private

        def inject_uri_sources_for(spec)
          spec.dependencies.each do |dep|
            next unless Namespaced::Gem::UriDependency.uri?(dep.name)

            uri_dep = Namespaced::Gem::UriDependency.parse(dep.name)
            version_reqs = dep.requirement.as_list

            # Add the namespaced source + gem, mirroring what the user would
            # write manually as:
            #   source "https://..." do
            #     gem "gem-name", "~> x.y"
            #   end
            source(uri_dep.source_url) do
              gem(uri_dep.gem_name, *version_reqs)
            end
          end
        end
      end
    end
  end
end
