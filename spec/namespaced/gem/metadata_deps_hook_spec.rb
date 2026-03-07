# frozen_string_literal: true

RSpec.describe Namespaced::Gem::MetadataDepsHook do
  describe ".register!" do
    it "is idempotent — safe to call multiple times" do
      expect { described_class.register! }.not_to raise_error
      expect { described_class.register! }.not_to raise_error
    end
  end

  describe ".parse_metadata_deps" do
    it "parses a single dep line" do
      raw = "https://beta.gem.coop/@myspace/foo ~> 1.0"
      result = described_class.parse_metadata_deps(raw)
      expect(result).to eq([
        ["https://beta.gem.coop/@myspace/foo", ["~> 1.0"]]
      ])
    end

    it "parses multiple dep lines" do
      raw = <<~DEPS
        https://beta.gem.coop/@myspace/foo ~> 1.0
        @myorg/bar >= 2.0
        pkg:gem/@myorg/baz ~> 3.0
      DEPS
      result = described_class.parse_metadata_deps(raw)
      expect(result).to eq([
        ["https://beta.gem.coop/@myspace/foo", ["~> 1.0"]],
        ["@myorg/bar", [">= 2.0"]],
        ["pkg:gem/@myorg/baz", ["~> 3.0"]]
      ])
    end

    it "parses multi-constraint versions" do
      raw = "https://beta.gem.coop/@ns/gem >= 1.0, < 3.0"
      result = described_class.parse_metadata_deps(raw)
      expect(result).to eq([
        ["https://beta.gem.coop/@ns/gem", [">= 1.0", "< 3.0"]]
      ])
    end

    it "defaults to >= 0 when no version is given" do
      raw = "https://beta.gem.coop/@ns/gem"
      result = described_class.parse_metadata_deps(raw)
      expect(result).to eq([
        ["https://beta.gem.coop/@ns/gem", [">= 0"]]
      ])
    end

    it "skips blank lines" do
      raw = <<~DEPS

        https://beta.gem.coop/@ns/foo ~> 1.0

        @myorg/bar >= 2.0

      DEPS
      result = described_class.parse_metadata_deps(raw)
      expect(result.size).to eq(2)
    end

    it "skips comment lines" do
      raw = <<~DEPS
        # This is a comment
        https://beta.gem.coop/@ns/foo ~> 1.0
        # Another comment
      DEPS
      result = described_class.parse_metadata_deps(raw)
      expect(result.size).to eq(1)
      expect(result[0][0]).to eq("https://beta.gem.coop/@ns/foo")
    end

    it "skips lines that are not valid URI deps" do
      raw = <<~DEPS
        https://beta.gem.coop/@ns/foo ~> 1.0
        rack ~> 3.0
        not-a-uri-dep
      DEPS
      result = described_class.parse_metadata_deps(raw)
      expect(result.size).to eq(1)
    end

    it "returns empty array for empty string" do
      expect(described_class.parse_metadata_deps("")).to eq([])
    end

    it "returns empty array for whitespace-only string" do
      expect(described_class.parse_metadata_deps("  \n  \n  ")).to eq([])
    end
  end

  describe ".process_spec" do
    let(:spec) do
      ::Gem::Specification.new do |s|
        s.name    = "test-gem"
        s.version = "1.0.0"
        s.summary = "test"
        s.authors = ["Test"]
      end
    end

    it "does nothing when metadata has no namespaced_dependencies" do
      expect(described_class).not_to receive(:install_namespace_deps)
      described_class.process_spec(spec)
    end

    it "does nothing when namespaced_dependencies is empty" do
      spec.metadata["namespaced_dependencies"] = ""
      expect(described_class).not_to receive(:install_namespace_deps)
      described_class.process_spec(spec)
    end

    it "calls install_namespace_deps when metadata has URI deps" do
      spec.metadata["namespaced_dependencies"] = "https://beta.gem.coop/@ns/foo ~> 1.0"
      expect(described_class).to receive(:install_namespace_deps).with(
        [["https://beta.gem.coop/@ns/foo", ["~> 1.0"]]],
        spec
      )
      described_class.process_spec(spec)
    end
  end

  describe ".process_batch" do
    it "processes each spec in the batch" do
      spec1 = ::Gem::Specification.new { |s| s.name = "a"; s.version = "1.0"; s.summary = "a"; s.authors = ["A"] }
      spec2 = ::Gem::Specification.new { |s| s.name = "b"; s.version = "1.0"; s.summary = "b"; s.authors = ["B"] }

      expect(described_class).to receive(:process_spec).with(spec1)
      expect(described_class).to receive(:process_spec).with(spec2)

      described_class.process_batch([spec1, spec2])
    end
  end

  describe "Namespaced::Gem.add_namespaced_dependency" do
    let(:spec) do
      ::Gem::Specification.new do |s|
        s.name    = "test-gem"
        s.version = "1.0.0"
        s.summary = "test"
        s.authors = ["Test"]
      end
    end

    it "adds the URI dep via add_dependency" do
      Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", "~> 1.0")
      dep = spec.dependencies.find { |d| d.name == "https://beta.gem.coop/@ns/foo" }
      expect(dep).not_to be_nil
      expect(dep.requirement.as_list).to eq(["~> 1.0"])
    end

    it "stores the dep in metadata" do
      Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", "~> 1.0")
      expect(spec.metadata["namespaced_dependencies"]).to eq("https://beta.gem.coop/@ns/foo ~> 1.0")
    end

    it "appends multiple deps to metadata" do
      Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", "~> 1.0")
      Namespaced::Gem.add_namespaced_dependency(spec, "@myorg/bar", ">= 2.0")
      expected = "https://beta.gem.coop/@ns/foo ~> 1.0\n@myorg/bar >= 2.0"
      expect(spec.metadata["namespaced_dependencies"]).to eq(expected)
    end

    it "handles multiple version constraints" do
      Namespaced::Gem.add_namespaced_dependency(spec, "https://beta.gem.coop/@ns/foo", ">= 1.0", "< 3.0")
      dep = spec.dependencies.find { |d| d.name == "https://beta.gem.coop/@ns/foo" }
      expect(dep.requirement.as_list).to contain_exactly(">= 1.0", "< 3.0")
      expect(spec.metadata["namespaced_dependencies"]).to eq("https://beta.gem.coop/@ns/foo >= 1.0, < 3.0")
    end
  end
end
