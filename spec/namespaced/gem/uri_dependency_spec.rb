# frozen_string_literal: true

RSpec.describe Namespaced::Gem::UriDependency do
  describe ".uri?" do
    context "with full HTTPS URI" do
      it "returns true for a gem.coop namespaced URI" do
        expect(described_class.uri?("https://beta.gem.coop/@myspace/my-gem")).to be true
      end

      it "returns true for a bare gem.coop URI" do
        expect(described_class.uri?("https://gem.coop/@org/tool")).to be true
      end

      it "returns true for any https server" do
        expect(described_class.uri?("https://gems.example.com/@ns/foo-bar")).to be true
      end

      it "returns true for http (non-TLS) URI" do
        expect(described_class.uri?("http://localhost:9292/@ns/foo")).to be true
      end
    end

    context "with shorthand @namespace/gem-name" do
      it "returns true" do
        expect(described_class.uri?("@myspace/my-gem")).to be true
      end

      it "returns true with underscored gem name" do
        expect(described_class.uri?("@org/my_gem")).to be true
      end
    end

    context "with traditional gem names" do
      it "returns false for a plain name" do
        expect(described_class.uri?("rack")).to be false
      end

      it "returns false for a hyphenated name" do
        expect(described_class.uri?("my-gem")).to be false
      end

      it "returns false for nil" do
        expect(described_class.uri?(nil)).to be false
      end

      it "returns false for a non-string" do
        expect(described_class.uri?(42)).to be false
      end
    end
  end

  describe ".parse" do
    subject(:dep) { described_class.parse(uri) }

    context "with a full HTTPS URI" do
      let(:uri) { "https://beta.gem.coop/@myspace/my-gem" }

      it "sets server_base" do
        expect(dep.server_base).to eq("https://beta.gem.coop")
      end

      it "sets namespace" do
        expect(dep.namespace).to eq("@myspace")
      end

      it "sets gem_name" do
        expect(dep.gem_name).to eq("my-gem")
      end

      it "builds source_url from server_base + namespace" do
        expect(dep.source_url).to eq("https://beta.gem.coop/@myspace")
      end

      it "preserves original" do
        expect(dep.original).to eq(uri)
      end
    end

    context "with shorthand @namespace/gem-name" do
      let(:uri) { "@myorg/tool_kit" }

      it "defaults server_base to gem.coop" do
        expect(dep.server_base).to eq("https://gem.coop")
      end

      it "sets namespace" do
        expect(dep.namespace).to eq("@myorg")
      end

      it "sets gem_name" do
        expect(dep.gem_name).to eq("tool_kit")
      end

      it "builds source_url correctly" do
        expect(dep.source_url).to eq("https://gem.coop/@myorg")
      end
    end

    context "with an invalid string" do
      it "raises ArgumentError" do
        expect { described_class.parse("not-a-uri") }.to raise_error(ArgumentError, /Not a valid URI dependency/)
      end
    end
  end

  describe "#to_s" do
    it "returns the canonical URI form" do
      dep = described_class.parse("https://beta.gem.coop/@ns/foo")
      expect(dep.to_s).to eq("https://beta.gem.coop/@ns/foo")
    end

    it "expands shorthand to full URI" do
      dep = described_class.parse("@ns/foo")
      expect(dep.to_s).to eq("https://gem.coop/@ns/foo")
    end
  end
end
