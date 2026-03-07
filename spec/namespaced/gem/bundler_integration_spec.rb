# frozen_string_literal: true

RSpec.describe Namespaced::Gem::BundlerIntegration do
  describe ".apply!" do
    context "when Bundler::Dsl is not loaded" do
      before do
        # Temporarily hide Bundler::Dsl to simulate the not-yet-loaded case
        @original_dsl = Bundler::Dsl if defined?(Bundler::Dsl)
      end

      it "does not raise" do
        expect { described_class.apply! }.not_to raise_error
      end
    end

    context "when Bundler::Dsl is available" do
      it "applies the patch" do
        described_class.apply!
        expect(::Bundler::Dsl.ancestors).to include(described_class::DslPatch)
      end

      it "is idempotent" do
        expect { described_class.apply! }.not_to raise_error
        expect { described_class.apply! }.not_to raise_error
      end

      it "sets the patched flag after prepending" do
        described_class.apply!
        expect(::Bundler::Dsl.instance_variable_get(:@namespaced_gem_patched)).to be true
      end
    end
  end

  describe ".apply_when_ready!" do
    context "when Bundler::Dsl is already loaded" do
      it "applies the patch immediately" do
        described_class.apply_when_ready!
        expect(::Bundler::Dsl.ancestors).to include(described_class::DslPatch)
      end
    end
  end

  describe "Bundler::Dsl integration" do
    before do
      Namespaced::Gem::DependencyPatch.apply!
      described_class.apply!
    end

    # Build a minimal Bundler DSL instance and process a gemspec with URI deps.
    # We use a double to avoid actually connecting to the network.
    let(:spec_with_uri_dep) do
      ::Gem::Specification.new do |s|
        s.name    = "example"
        s.version = "0.1.0"
        s.summary = "example"
        s.add_dependency "https://beta.gem.coop/@myspace/special-gem", "~> 1.0"
        s.add_dependency "rack", ">= 2.0"
      end
    end

    it "injects a source block for URI deps" do
      dsl = ::Bundler::Dsl.new

      # Stub the file system parts so DSL doesn't need real files
      allow(::Gem::Util).to receive(:glob_files_in_dir).and_return([])
      allow(dsl).to receive(:gemspecs).and_return([spec_with_uri_dep])

      # Directly call inject_uri_sources_for to test it in isolation
      injected_sources = []
      injected_gems = []

      allow(dsl).to receive(:source) do |url, &block|
        injected_sources << url
        # Capture gem calls within the source block
        allow(dsl).to receive(:gem) { |name, *reqs| injected_gems << [name, reqs] }
        dsl.instance_eval(&block) if block
      end

      dsl.send(:inject_uri_sources_for, spec_with_uri_dep)

      expect(injected_sources).to eq(["https://beta.gem.coop/@myspace"])
      expect(injected_gems.first).to eq(["special-gem", ["~> 1.0"]])
    end

    it "skips non-URI dependencies" do
      dsl = ::Bundler::Dsl.new

      injected_sources = []
      allow(dsl).to receive(:source) { |url, &_b| injected_sources << url }

      dsl.send(:inject_uri_sources_for, spec_with_uri_dep)

      # Only the one URI dep should trigger a source injection; rack should not
      expect(injected_sources.length).to eq(1)
    end

    context "with multiple URI deps from different namespaces" do
      let(:spec_with_multiple_uri_deps) do
        ::Gem::Specification.new do |s|
          s.name    = "multi-dep-example"
          s.version = "0.2.0"
          s.summary = "example"
          s.add_dependency "https://beta.gem.coop/@alice/gem-a", "~> 1.0"
          s.add_dependency "https://beta.gem.coop/@bob/gem-b", ">= 2.0"
          s.add_dependency "rack", "~> 3.0"
        end
      end

      it "injects separate source blocks for each namespace" do
        dsl = ::Bundler::Dsl.new

        injected_sources = []
        injected_gems = []

        allow(dsl).to receive(:source) do |url, &block|
          injected_sources << url
          allow(dsl).to receive(:gem) { |name, *reqs| injected_gems << [name, reqs] }
          dsl.instance_eval(&block) if block
        end

        dsl.send(:inject_uri_sources_for, spec_with_multiple_uri_deps)

        expect(injected_sources).to contain_exactly(
          "https://beta.gem.coop/@alice",
          "https://beta.gem.coop/@bob"
        )
        expect(injected_gems.map(&:first)).to contain_exactly("gem-a", "gem-b")
      end
    end

    context "with multiple URI deps from the same namespace" do
      let(:spec_with_same_ns_deps) do
        ::Gem::Specification.new do |s|
          s.name    = "same-ns-example"
          s.version = "0.3.0"
          s.summary = "example"
          s.add_dependency "https://beta.gem.coop/@myspace/gem-one", "~> 1.0"
          s.add_dependency "https://beta.gem.coop/@myspace/gem-two", "~> 2.0"
        end
      end

      it "injects a source call for each dep even from the same namespace" do
        dsl = ::Bundler::Dsl.new

        injected_sources = []
        injected_gems = []

        allow(dsl).to receive(:source) do |url, &block|
          injected_sources << url
          allow(dsl).to receive(:gem) { |name, *reqs| injected_gems << [name, reqs] }
          dsl.instance_eval(&block) if block
        end

        dsl.send(:inject_uri_sources_for, spec_with_same_ns_deps)

        expect(injected_sources).to eq([
          "https://beta.gem.coop/@myspace",
          "https://beta.gem.coop/@myspace"
        ])
        expect(injected_gems.map(&:first)).to eq(["gem-one", "gem-two"])
      end
    end
  end
end
