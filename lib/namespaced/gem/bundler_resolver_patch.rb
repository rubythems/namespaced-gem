# frozen_string_literal: true

require_relative "uri_dependency"

module Namespaced
  module Gem
    # Patches Bundler's resolver and definition to handle URI-named transitive
    # dependencies — i.e., deps that appear in *remote* gemspecs of gems that
    # the user's Gemfile directly requests.
    #
    # When Bundler resolves orig-foo from rubygems.org and orig-foo's gemspec
    # declares:
    #   spec.add_dependency "https://beta.gem.coop/@pboling/foo", "~> 1.0"
    #
    # Bundler's resolver encounters "https://beta.gem.coop/@pboling/foo" as a
    # dep name during resolution. Without this patch it looks up that literal
    # string on rubygems.org and fails.
    #
    # This patch hooks two points:
    #   1. Bundler::Definition#initialize — handles URI deps that arrive via
    #      the Gemfile / gemspec DSL (direct deps) by remapping them and
    #      injecting the correct Rubygems source into the SourceList.
    #   2. Bundler::Resolver#to_dependency_hash — handles URI deps discovered
    #      as transitive deps during resolution by remapping to real gem names
    #      and registering the namespace source in @source_requirements.
    module BundlerResolverPatch
      def self.apply!
        return unless defined?(::Bundler)
        return if ::Bundler::Definition.instance_variable_get(:@namespaced_gem_resolver_patched)

        ::Bundler::Definition.prepend(DefinitionPatch)
        ::Bundler::Resolver.prepend(ResolverPatch)
        ::Bundler::Definition.instance_variable_set(:@namespaced_gem_resolver_patched, true)
      end

      def self.apply_when_ready!
        if defined?(::Bundler::Definition)
          apply!
        else
          trace = TracePoint.new(:end) do |tp|
            next unless tp.self == ::Bundler::Definition rescue next

            apply!
            trace.disable
          end
          trace.enable
        end
      end

      # Patched into Bundler::Definition to remap URI deps in @dependencies
      # (the deps that come directly from the Gemfile / gemspec DSL).
      module DefinitionPatch
        def initialize(lockfile, dependencies, sources, unlock, ruby_version = nil, optional_groups = [], gemfiles = [])
          remapped, new_sources = remap_uri_dependencies(dependencies, sources)
          new_sources.each { |src| sources.add_rubygems_source("remotes" => [src]) }
          super(lockfile, remapped, sources, unlock, ruby_version, optional_groups, gemfiles)
        end

        private

        def remap_uri_dependencies(dependencies, _sources)
          new_sources = []
          remapped = dependencies.map do |dep|
            next dep unless Namespaced::Gem::UriDependency.uri?(dep.name)

            uri_dep = Namespaced::Gem::UriDependency.parse(dep.name)
            new_sources << uri_dep.source_url

            ::Bundler::Dependency.new(
              uri_dep.gem_name,
              dep.requirement,
              dep_options_for(dep, uri_dep.source_url)
            )
          end
          [remapped, new_sources.uniq]
        end

        def dep_options_for(dep, source_url)
          opts = {}
          opts["source"] = source_url
          opts["gemfile"] = dep.respond_to?(:gemfile) ? dep.gemfile : nil
          opts
        end
      end

      # Patched into Bundler::Resolver to remap URI deps that appear as
      # transitive deps of remotely-fetched gemspecs during resolution.
      module ResolverPatch
        def to_dependency_hash(dependencies, packages)
          remapped = dependencies.flat_map do |dep|
            next [dep] unless Namespaced::Gem::UriDependency.uri?(dep.name)

            uri_dep = Namespaced::Gem::UriDependency.parse(dep.name)

            # Ensure the resolver knows about a source for the real gem name.
            unless @source_requirements.key?(uri_dep.gem_name)
              source = ::Bundler::Source::Rubygems.new
              source.add_remote(uri_dep.source_url)
              @source_requirements[uri_dep.gem_name] = source
            end

            [::Gem::Dependency.new(uri_dep.gem_name, dep.requirement, dep.type)]
          end

          super(remapped, packages)
        end
      end
    end
  end
end
