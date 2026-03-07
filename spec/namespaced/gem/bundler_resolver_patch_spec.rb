# frozen_string_literal: true

RSpec.describe Namespaced::Gem::BundlerResolverPatch do
  before do
    Namespaced::Gem::DependencyPatch.apply!
    described_class.apply!
  end

  describe ".apply!" do
    it "is idempotent" do
      expect { described_class.apply! }.not_to raise_error
    end

    it "prepends DefinitionPatch onto Bundler::Definition" do
      expect(::Bundler::Definition.ancestors).to include(described_class::DefinitionPatch)
    end

    it "prepends ResolverPatch onto Bundler::Resolver" do
      expect(::Bundler::Resolver.ancestors).to include(described_class::ResolverPatch)
    end
  end

  # Test the remapping logic by mixing it into a plain test object.
  describe "DefinitionPatch remapping logic" do
    let(:test_host) do
      Object.new.tap { |o| o.extend(described_class::DefinitionPatch) }
    end

    let(:uri_dep)   { ::Bundler::Dependency.new("https://beta.gem.coop/@pboling/foo", "~> 1.0") }
    let(:plain_dep) { ::Bundler::Dependency.new("rack", ">= 2.0") }

    def remap(deps)
      test_host.send(:remap_uri_dependencies, deps)
    end

    it "remaps URI deps to real gem names" do
      remapped, = remap([uri_dep, plain_dep])
      expect(remapped.map(&:name)).to eq(["foo", "rack"])
    end

    it "collects the namespace source URL" do
      _, new_sources = remap([uri_dep])
      expect(new_sources).to eq(["https://beta.gem.coop/@pboling"])
    end

    it "preserves version requirements" do
      remapped, = remap([uri_dep])
      expect(remapped.first.requirement.as_list).to eq(["~> 1.0"])
    end

    it "deduplicates source URLs when multiple deps share a namespace" do
      dep2 = ::Bundler::Dependency.new("https://beta.gem.coop/@pboling/bar", "~> 2.0")
      _, new_sources = remap([uri_dep, dep2])
      expect(new_sources).to eq(["https://beta.gem.coop/@pboling"])
    end

    it "leaves non-URI deps unchanged" do
      remapped, new_sources = remap([plain_dep])
      expect(remapped.map(&:name)).to eq(["rack"])
      expect(new_sources).to be_empty
    end
  end

  describe "Bundler::Resolver::ResolverPatch" do
    # Build a minimal resolver backed by a fake Base.
    let(:src_reqs) { { default: double("default_source") } }

    let(:base) do
      double("base",
        source_requirements: src_reqs,
        requirements: [],
        packages: {},
        locked_specs: double("locked_specs", empty?: true),
      )
    end

    let(:resolver) { ::Bundler::Resolver.new(base, double("promoter")) }
    let(:packages) { Hash.new { |h, k| h[k] = double("pkg_#{k}", name: k) } }

    let(:uri_dep)   { ::Gem::Dependency.new("https://beta.gem.coop/@pboling/foo", "~> 1.0") }
    let(:plain_dep) { ::Gem::Dependency.new("rack", ">= 2.0") }

    describe "#to_dependency_hash" do
      it "registers a Bundler::Source::Rubygems in @source_requirements for the real gem name" do
        # Stub add_remote to avoid network calls
        allow_any_instance_of(::Bundler::Source::Rubygems).to receive(:add_remote)

        begin
          resolver.send(:to_dependency_hash, [uri_dep, plain_dep], packages)
        rescue StandardError
          nil # super may fail without full context; we just check the side-effect
        end

        expect(src_reqs.key?("foo")).to be true
        expect(src_reqs["foo"]).to be_a(::Bundler::Source::Rubygems)
      end

      it "does not register a source entry for non-URI deps" do
        allow_any_instance_of(::Bundler::Source::Rubygems).to receive(:add_remote)

        begin
          resolver.send(:to_dependency_hash, [plain_dep], packages)
        rescue StandardError
          nil
        end

        expect(src_reqs.key?("rack")).to be false
      end

      it "is idempotent — does not overwrite an existing source entry" do
        existing_source = double("existing_source")
        src_reqs["foo"] = existing_source

        begin
          resolver.send(:to_dependency_hash, [uri_dep], packages)
        rescue StandardError
          nil
        end

        expect(src_reqs["foo"]).to equal(existing_source)
      end
    end
  end
end
