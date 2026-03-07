# frozen_string_literal: true

RSpec.describe Namespaced::Gem do
  it "has a version number" do
    expect(Namespaced::Gem::VERSION).not_to be nil
  end

  it "does something useful" do
    expect(false).to eq(true)
  end
end
