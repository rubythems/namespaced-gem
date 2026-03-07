# frozen_string_literal: true

RSpec.describe Namespaced::Gem::DependencyPatch do
  describe ".apply!" do
    it "is idempotent — safe to call multiple times" do
      expect { described_class.apply! }.not_to raise_error
      expect { described_class.apply! }.not_to raise_error
    end

    it "marks Gem::Dependency as patched" do
      described_class.apply!
      expect(::Gem::Dependency.instance_variable_get(:@namespaced_gem_patched)).to be true
    end

    it "prepends InstanceMethods onto Gem::Dependency" do
      described_class.apply!
      expect(::Gem::Dependency.ancestors).to include(described_class::InstanceMethods)
    end
  end

  describe "Gem::Dependency after patching" do
    before { described_class.apply! }

    context "with a traditional gem name" do
      it "creates a dependency normally" do
        dep = ::Gem::Dependency.new("rack", ">= 0")
        expect(dep.name).to eq("rack")
      end

      it "does not mark it as uri_gem?" do
        dep = ::Gem::Dependency.new("rack", ">= 0")
        expect(dep.uri_gem?).to be false
      end

      it "returns nil for uri_dependency" do
        dep = ::Gem::Dependency.new("rack", ">= 0")
        expect(dep.uri_dependency).to be_nil
      end
    end

    context "with a full HTTPS URI name" do
      let(:uri) { "https://beta.gem.coop/@myspace/my-gem" }

      it "does not raise on creation" do
        expect { ::Gem::Dependency.new(uri, ">= 0") }.not_to raise_error
      end

      it "preserves the URI as the dependency name" do
        dep = ::Gem::Dependency.new(uri, ">= 0")
        expect(dep.name).to eq(uri)
      end

      it "is identified as a URI gem" do
        dep = ::Gem::Dependency.new(uri, ">= 0")
        expect(dep.uri_gem?).to be true
      end

      it "exposes a parsed UriDependency" do
        dep = ::Gem::Dependency.new(uri, ">= 0")
        expect(dep.uri_dependency).to be_a(Namespaced::Gem::UriDependency)
        expect(dep.uri_dependency.gem_name).to eq("my-gem")
        expect(dep.uri_dependency.source_url).to eq("https://beta.gem.coop/@myspace")
      end

      it "carries version requirements through normally" do
        dep = ::Gem::Dependency.new(uri, "~> 1.2")
        expect(dep.requirement.as_list).to eq(["~> 1.2"])
      end
    end

    context "with shorthand @namespace/gem-name" do
      let(:uri) { "@ns/tool" }

      it "does not raise on creation" do
        expect { ::Gem::Dependency.new(uri) }.not_to raise_error
      end

      it "is identified as a URI gem" do
        dep = ::Gem::Dependency.new(uri)
        expect(dep.uri_gem?).to be true
      end

      it "exposes a parsed UriDependency with default server" do
        dep = ::Gem::Dependency.new(uri)
        expect(dep.uri_dependency.server_base).to eq("https://gem.coop")
        expect(dep.uri_dependency.gem_name).to eq("tool")
      end
    end
  end

  describe "Gem::Specification#add_dependency" do
    before { described_class.apply! }

    it "accepts a URI dependency" do
      spec = ::Gem::Specification.new do |s|
        s.name = "test-gem"
        s.version = "1.0.0"
        s.summary = "test"
        s.add_dependency "https://beta.gem.coop/@myspace/my-gem", "~> 1.0"
      end

      uri_deps = spec.dependencies.select(&:uri_gem?)
      expect(uri_deps.length).to eq(1)
      expect(uri_deps.first.uri_dependency.gem_name).to eq("my-gem")
    end

    it "still accepts traditional dependencies alongside URI ones" do
      spec = ::Gem::Specification.new do |s|
        s.name = "test-gem"
        s.version = "1.0.0"
        s.summary = "test"
        s.add_dependency "rack", ">= 2.0"
        s.add_dependency "https://beta.gem.coop/@ns/special", "~> 0.1"
      end

      expect(spec.dependencies.count).to eq(2)
      expect(spec.dependencies.map(&:uri_gem?)).to eq([false, true])
    end
  end
end
