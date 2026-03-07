# frozen_string_literal: true

RSpec.describe Namespaced::Gem::NamespaceSourceRegistry do
  after { described_class.clear! }

  describe ".register / .namespace_source_url?" do
    it "registers a source URL and recognizes it" do
      described_class.register("https://beta.gem.coop/@kaspth")
      expect(described_class.namespace_source_url?("https://beta.gem.coop/@kaspth")).to be true
    end

    it "normalizes trailing slashes when registering" do
      described_class.register("https://beta.gem.coop/@kaspth/")
      expect(described_class.namespace_source_url?("https://beta.gem.coop/@kaspth")).to be true
    end

    it "normalizes trailing slashes when querying" do
      described_class.register("https://beta.gem.coop/@kaspth")
      expect(described_class.namespace_source_url?("https://beta.gem.coop/@kaspth/")).to be true
    end

    it "returns false for unregistered URLs" do
      expect(described_class.namespace_source_url?("https://rubygems.org")).to be false
    end

    it "is idempotent — registering the same URL twice is harmless" do
      described_class.register("https://beta.gem.coop/@kaspth")
      described_class.register("https://beta.gem.coop/@kaspth")
      expect(described_class.registered_urls.count("https://beta.gem.coop/@kaspth")).to eq(1)
    end

    it "accepts URI objects as well as strings" do
      uri = Gem::URI.parse("https://beta.gem.coop/@pboling")
      described_class.register(uri)
      expect(described_class.namespace_source_url?(uri)).to be true
    end
  end

  describe ".namespace_source?" do
    it "returns true for a Gem::Source whose URI was registered" do
      described_class.register("https://beta.gem.coop/@kaspth")
      source = ::Gem::Source.new("https://beta.gem.coop/@kaspth")
      expect(described_class.namespace_source?(source)).to be true
    end

    it "returns true for a Gem::Source whose URI was registered (with trailing slash)" do
      described_class.register("https://beta.gem.coop/@kaspth")
      source = ::Gem::Source.new("https://beta.gem.coop/@kaspth/")
      expect(described_class.namespace_source?(source)).to be true
    end

    it "returns false for a Gem::Source whose URI was NOT registered" do
      source = ::Gem::Source.new("https://rubygems.org")
      expect(described_class.namespace_source?(source)).to be false
    end

    it "returns false for non-Source objects" do
      expect(described_class.namespace_source?("https://beta.gem.coop/@kaspth")).to be false
    end

    it "returns false for nil" do
      expect(described_class.namespace_source?(nil)).to be false
    end
  end

  describe ".clear!" do
    it "removes all registered sources" do
      described_class.register("https://beta.gem.coop/@kaspth")
      described_class.register("https://beta.gem.coop/@pboling")
      described_class.clear!
      expect(described_class.registered_urls).to be_empty
    end
  end

  describe ".registered_urls" do
    it "returns all registered URLs" do
      described_class.register("https://beta.gem.coop/@kaspth")
      described_class.register("https://beta.gem.coop/@pboling")
      expect(described_class.registered_urls).to contain_exactly(
        "https://beta.gem.coop/@kaspth",
        "https://beta.gem.coop/@pboling"
      )
    end
  end
end
