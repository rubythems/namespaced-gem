# frozen_string_literal: true

RSpec.describe Namespaced::Gem do
  it "has a version number" do
    expect(Namespaced::Gem::VERSION).not_to be nil
  end

  it "has a version string matching semver pattern" do
    expect(Namespaced::Gem::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "exposes UriDependency" do
    expect(Namespaced::Gem::UriDependency).to be_a(Class)
  end

  it "exposes DependencyPatch" do
    expect(Namespaced::Gem::DependencyPatch).to be_a(Module)
  end

  it "exposes BundlerIntegration" do
    expect(Namespaced::Gem::BundlerIntegration).to be_a(Module)
  end

  it "exposes BundlerResolverPatch" do
    expect(Namespaced::Gem::BundlerResolverPatch).to be_a(Module)
  end

  it "exposes GemResolverPatch" do
    expect(Namespaced::Gem::GemResolverPatch).to be_a(Module)
  end

  it "defines a custom Error class" do
    expect(Namespaced::Gem::Error).to be < StandardError
  end
end
