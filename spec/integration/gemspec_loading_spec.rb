# frozen_string_literal: true

RSpec.describe "Loading a gemspec with URI dependencies" do
  let(:fixture_dir) { File.expand_path("../fixtures/dummy_gem", __dir__) }

  let(:spec) do
    Namespaced::Gem::DependencyPatch.apply!
    # Load the gemspec the same way Bundler / RubyGems would.
    ::Gem::Specification.load(File.join(fixture_dir, "dummy_gem.gemspec"))
  end

  it "loads the gemspec without error" do
    expect(spec).to be_a(::Gem::Specification)
    expect(spec.name).to eq("dummy_gem")
  end

  it "contains both traditional and URI dependencies" do
    names = spec.dependencies.map(&:name)
    expect(names).to include("rake")
    expect(names).to include("https://beta.gem.coop/@kaspth/oaken")
  end

  it "marks the URI dependency as uri_gem?" do
    oaken_dep = spec.dependencies.find { |d| d.name.include?("oaken") }
    expect(oaken_dep.uri_gem?).to be true
  end

  it "does not mark the traditional dependency as uri_gem?" do
    rake_dep = spec.dependencies.find { |d| d.name == "rake" }
    expect(rake_dep.uri_gem?).to be false
  end

  it "parses the URI dependency into its components" do
    oaken_dep = spec.dependencies.find { |d| d.name.include?("oaken") }
    uri = oaken_dep.uri_dependency

    expect(uri.server_base).to eq("https://beta.gem.coop")
    expect(uri.namespace).to eq("@kaspth")
    expect(uri.gem_name).to eq("oaken")
    expect(uri.source_url).to eq("https://beta.gem.coop/@kaspth")
  end

  it "preserves version requirements on the URI dependency" do
    oaken_dep = spec.dependencies.find { |d| d.name.include?("oaken") }
    expect(oaken_dep.requirement.as_list).to eq(["~> 1.0"])
  end

  describe "Bundler DSL source injection" do
    before do
      Namespaced::Gem::DependencyPatch.apply!
      Namespaced::Gem::BundlerIntegration.apply!
    end

    it "injects the correct source block for the URI dep" do
      dsl = ::Bundler::Dsl.new

      injected_sources = []
      injected_gems = []

      allow(dsl).to receive(:source) do |url, &block|
        injected_sources << url
        allow(dsl).to receive(:gem) { |name, *reqs| injected_gems << [name, reqs] }
        dsl.instance_eval(&block) if block
      end

      dsl.send(:inject_uri_sources_for, spec)

      expect(injected_sources).to include("https://beta.gem.coop/@kaspth")
      oaken_entry = injected_gems.find { |name, _| name == "oaken" }
      expect(oaken_entry).not_to be_nil
      expect(oaken_entry.last).to eq(["~> 1.0"])
    end

    it "does not inject a source for the traditional dep" do
      dsl = ::Bundler::Dsl.new

      injected_sources = []
      allow(dsl).to receive(:source) do |url, &block|
        injected_sources << url
        allow(dsl).to receive(:gem) { |*| }
        dsl.instance_eval(&block) if block
      end

      dsl.send(:inject_uri_sources_for, spec)

      expect(injected_sources).not_to include(a_string_matching(/rubygems/))
      expect(injected_sources.length).to eq(1)
    end
  end
end
