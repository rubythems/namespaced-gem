# frozen_string_literal: true

RSpec.describe Namespaced::Gem do
  it "has a version number" do
    expect(Namespaced::Gem::VERSION).not_to be nil
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
end

