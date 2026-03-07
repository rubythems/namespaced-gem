# frozen_string_literal: true

RSpec.describe Namespaced::Gem::ApiSpecPatch do
  before do
    described_class.apply!
  end

  after do
    Namespaced::Gem::NamespaceSourceRegistry.clear!
  end

  describe ".apply!" do
    it "is idempotent" do
      expect { described_class.apply! }.not_to raise_error
    end

    it "prepends SpecPatch onto Gem::Resolver::APISpecification" do
      expect(::Gem::Resolver::APISpecification.ancestors).to include(described_class::SpecPatch)
    end

    it "sets the patched flag" do
      expect(
        ::Gem::Resolver::APISpecification.instance_variable_get(:@namespaced_gem_api_spec_patched)
      ).to be true
    end
  end

  describe "SpecPatch#spec" do
    let(:namespace_source_url) { "https://beta.gem.coop/@kaspth" }
    let(:dep_uri) { "#{namespace_source_url}/info/" }

    # Build a Gem::Resolver::APISet that points to the namespace source.
    let(:api_set) do
      set = ::Gem::Resolver::APISet.allocate
      set.instance_variable_set(:@dep_uri, Gem::URI.parse(dep_uri))
      set.instance_variable_set(:@uri, Gem::URI.parse(namespace_source_url + "/"))
      set.instance_variable_set(:@source, ::Gem::Source.new(namespace_source_url + "/"))
      set.instance_variable_set(:@data, {})
      set.instance_variable_set(:@to_fetch, [])
      set.instance_variable_set(:@remote, true)
      set.instance_variable_set(:@prerelease, false)
      set
    end

    let(:api_data) do
      {
        name: "oaken",
        number: "2.5.1",
        platform: "ruby",
        dependencies: [["activerecord", ">= 7.0"]],
        requirements: { ruby: ">= 3.1.0", rubygems: ">= 3.3.0" },
      }
    end

    # Clear the APISpecification cache to avoid leaking between tests.
    before do
      ::Gem::Resolver::APISpecification.class_variable_set(:@@cache, {})
    end

    context "when the source IS a registered namespace source" do
      before do
        Namespaced::Gem::NamespaceSourceRegistry.register(namespace_source_url)
      end

      it "returns a synthesized Gem::Specification without hitting the network" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)

        # Should NOT call source.fetch_spec — if it did, it would raise
        # because the source isn't a real server.
        spec = api_spec.spec

        expect(spec).to be_a(::Gem::Specification)
        expect(spec.name).to eq("oaken")
        expect(spec.version).to eq(::Gem::Version.new("2.5.1"))
        expect(spec.platform).to eq(::Gem::Platform.new("ruby"))
      end

      it "populates dependencies from the Compact Index data" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)
        spec = api_spec.spec

        dep_names = spec.dependencies.map(&:name)
        expect(dep_names).to include("activerecord")

        ar_dep = spec.dependencies.find { |d| d.name == "activerecord" }
        expect(ar_dep.requirement.as_list).to eq([">= 7.0"])
      end

      it "populates required_ruby_version from the Compact Index data" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)
        spec = api_spec.spec

        expect(spec.required_ruby_version).to eq(::Gem::Requirement.new(">= 3.1.0"))
      end

      it "populates required_rubygems_version from the Compact Index data" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)
        spec = api_spec.spec

        expect(spec.required_rubygems_version).to eq(::Gem::Requirement.new(">= 3.3.0"))
      end

      it "caches the synthesized spec (returns the same object)" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)
        spec1 = api_spec.spec
        spec2 = api_spec.spec
        expect(spec1).to equal(spec2) # same object identity
      end

      it "handles gems with no dependencies" do
        no_deps_data = api_data.merge(dependencies: [])
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, no_deps_data)
        spec = api_spec.spec

        expect(spec.dependencies).to be_empty
      end

      it "handles platform-specific gems" do
        platform_data = api_data.merge(platform: "x86_64-linux")
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, platform_data)
        spec = api_spec.spec

        expect(spec.platform).to eq(::Gem::Platform.new("x86_64-linux"))
      end
    end

    context "when the source is NOT a registered namespace source" do
      it "delegates to the original #spec (super)" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)

        # The original #spec will try to fetch_spec from the fake source and fail.
        # We just verify it doesn't go through our synthesis path.
        expect do
          api_spec.spec
        end.to raise_error(StandardError) # fetch_spec will fail on a non-real source
      end
    end
  end

  describe "SpecPatch#fetch_development_dependencies" do
    let(:namespace_source_url) { "https://beta.gem.coop/@kaspth" }

    let(:api_set) do
      set = ::Gem::Resolver::APISet.allocate
      set.instance_variable_set(:@dep_uri, Gem::URI.parse("#{namespace_source_url}/info/"))
      set.instance_variable_set(:@uri, Gem::URI.parse(namespace_source_url + "/"))
      set.instance_variable_set(:@source, ::Gem::Source.new(namespace_source_url + "/"))
      set.instance_variable_set(:@data, {})
      set.instance_variable_set(:@to_fetch, [])
      set.instance_variable_set(:@remote, true)
      set.instance_variable_set(:@prerelease, false)
      set
    end

    let(:api_data) do
      {
        name: "oaken",
        number: "2.5.1",
        platform: "ruby",
        dependencies: [["activerecord", ">= 7.0"]],
        requirements: {},
      }
    end

    before do
      ::Gem::Resolver::APISpecification.class_variable_set(:@@cache, {})
    end

    context "when the source IS a registered namespace source" do
      before do
        Namespaced::Gem::NamespaceSourceRegistry.register(namespace_source_url)
      end

      it "is a no-op (does not hit the network)" do
        api_spec = ::Gem::Resolver::APISpecification.new(api_set, api_data)

        # Should not raise — just returns nil.
        expect(api_spec.fetch_development_dependencies).to be_nil
      end
    end
  end
end
