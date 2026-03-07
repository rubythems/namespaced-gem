# frozen_string_literal: true

require_relative "uri_dependency"

module Namespaced
  module Gem
    # Implements a `Gem.done_installing` hook that processes deferred
    # namespace dependencies stored in a gem's metadata.
    #
    # ## Why This Exists
    #
    # When `gem install my-gem` runs and `namespaced-gem` is listed as a
    # runtime dependency of `my-gem`, the following sequence occurs:
    #
    #   1. RubyGems resolves ALL dependencies before installing ANY.
    #   2. URI-style deps (e.g. "https://beta.gem.coop/@ns/foo") can't be
    #      resolved on rubygems.org — they'd cause resolution to fail.
    #   3. After resolution, gems install in topological order (leaves first).
    #   4. `namespaced-gem` installs first → `load_plugin` fires →
    #      `rubygems_plugin.rb` is hot-loaded → this hook registers.
    #   5. After ALL gems in the batch finish installing, `done_installing`
    #      fires and this hook processes the deferred namespace deps.
    #
    # ## Gemspec Convention
    #
    # Gem authors encode namespace dependencies in metadata:
    #
    #   spec.metadata["namespaced_dependencies"] = <<~DEPS
    #     https://beta.gem.coop/@myspace/foo ~> 1.0
    #     @myorg/bar >= 2.0
    #     pkg:gem/@myorg/baz ~> 3.0
    #   DEPS
    #
    # Each line is: `<uri-name> <version-constraint>...`
    #
    # For Bundler workflows, the same deps should ALSO be declared via
    # `add_dependency` (Bundler handles URI deps natively via
    # BundlerIntegration). The metadata field is only needed for the
    # `gem install` code path.
    #
    # ## Helper for Gem Authors
    #
    # Use `Namespaced::Gem.add_namespaced_dependency` in your gemspec to
    # automatically write both `add_dependency` and the metadata field:
    #
    #   Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", "~> 1.0")
    #
    module MetadataDepsHook
      METADATA_KEY = "namespaced_dependencies"

      # Register the done_installing hook. Called from rubygems_plugin.rb.
      def self.register!
        return if @registered

        ::Gem.done_installing do |_dep_installer, specs|
          MetadataDepsHook.process_batch(specs)
        end

        @registered = true
      end

      # Process a batch of just-installed gem specs, looking for deferred
      # namespace dependencies in their metadata.
      def self.process_batch(specs)
        specs.each do |spec|
          process_spec(spec)
        end
      end

      # Process a single spec's metadata for namespace dependencies.
      def self.process_spec(spec)
        raw = spec.metadata[METADATA_KEY]
        return unless raw.is_a?(String) && !raw.strip.empty?

        deps = parse_metadata_deps(raw)
        return if deps.empty?

        install_namespace_deps(deps, spec)
      end

      # Parse the metadata string into an array of [uri_name, version_constraints].
      #
      # Format: one dep per line, `<uri-name> <version constraints...>`
      #   https://beta.gem.coop/@myspace/foo ~> 1.0
      #   @myorg/bar >= 2.0, < 3.0
      #   pkg:gem/@myorg/baz ~> 3.0
      def self.parse_metadata_deps(raw)
        raw.strip.lines.filter_map do |line|
          line = line.strip
          next if line.empty? || line.start_with?("#")

          # Split into URI name and version constraints.
          # The URI name is the first whitespace-delimited token.
          parts = line.split(/\s+/, 2)
          uri_name = parts[0]
          version_str = parts[1]

          next unless UriDependency.uri?(uri_name)

          version_reqs = if version_str && !version_str.strip.empty?
                           # Split on comma for multiple constraints: "~> 1.0, < 2.0"
                           version_str.split(",").map(&:strip).reject(&:empty?)
                         else
                           [">= 0"]
                         end

          [uri_name, version_reqs]
        end
      end

      # Install namespace dependencies using the now-active patches.
      #
      # At this point, rubygems_plugin.rb has been hot-loaded, so:
      #   - DependencyPatch is active (uri_gem?, uri_dependency)
      #   - GemResolverPatch is active (RequestSet/InstallerSet handle URI deps)
      #   - ApiSpecPatch is active (synthesizes specs from Compact Index)
      #   - DownloadPatch is active (clear namespace download errors)
      def self.install_namespace_deps(deps, parent_spec)
        deps.each do |uri_name, version_reqs|
          uri_dep = UriDependency.parse(uri_name)

          warn "[namespaced-gem] Installing deferred namespace dependency: " \
               "#{uri_dep.gem_name} (#{version_reqs.join(", ")}) " \
               "from #{uri_dep.source_url} " \
               "(required by #{parent_spec.name})"

          begin
            installer = ::Gem::DependencyInstaller.new(
              domain: :both,
              force: false,
              # Let the user's existing gem path config apply
            )
            # The GemResolverPatch will intercept this URI dep during
            # resolution and route it to the correct namespace source.
            installer.install(uri_name, ::Gem::Requirement.new(*version_reqs))
          rescue ::Gem::UnsatisfiableDependencyError, Namespaced::Gem::Error => e
            warn "[namespaced-gem] WARNING: Failed to install namespace dependency " \
                 "#{uri_dep.gem_name} from #{uri_dep.source_url}: #{e.message}"
            warn "[namespaced-gem]   This may be a server-side issue. See ISSUE.md."
          end
        end
      end
    end

    # Convenience method for gem authors to declare a namespaced dependency
    # in both `add_dependency` (for Bundler) and `metadata` (for gem install).
    #
    # Usage in gemspec:
    #   require "namespaced/gem"
    #   Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", "~> 1.0")
    #
    def self.add_namespaced_dependency(spec, uri_name, *version_constraints)
      # Standard add_dependency — works with Bundler via BundlerIntegration
      spec.add_dependency(uri_name, *version_constraints)

      # Also store in metadata for the gem install hot-load path
      version_str = version_constraints.join(", ")
      entry = "#{uri_name} #{version_str}"

      existing = spec.metadata[MetadataDepsHook::METADATA_KEY]
      spec.metadata[MetadataDepsHook::METADATA_KEY] = if existing && !existing.strip.empty?
                                                         "#{existing.strip}\n#{entry}"
                                                       else
                                                         entry
                                                       end
    end
  end
end
