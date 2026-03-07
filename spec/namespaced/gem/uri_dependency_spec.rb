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

      it "returns true for a URI with a port number" do
        expect(described_class.uri?("https://gems.example.com:8443/@ns/my-gem")).to be true
      end
    end

    context "with gem names containing dots" do
      it "returns true for full URI with dotted gem name" do
        expect(described_class.uri?("https://beta.gem.coop/@ns/my.gem")).to be true
      end

      it "returns true for shorthand with dotted gem name" do
        expect(described_class.uri?("@ns/my.gem.name")).to be true
      end
    end

    context "with shorthand @namespace/gem-name" do
      it "returns true" do
        expect(described_class.uri?("@myspace/my-gem")).to be true
      end

      it "returns true with underscored gem name" do
        expect(described_class.uri?("@org/my_gem")).to be true
      end

      it "returns true with complex namespace" do
        expect(described_class.uri?("@my-org.team/tool")).to be true
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

      it "returns false for an empty string" do
        expect(described_class.uri?("")).to be false
      end

      it "returns false for a bare @ without slash" do
        expect(described_class.uri?("@namespace")).to be false
      end

      it "returns false for a URI with trailing slash" do
        expect(described_class.uri?("https://beta.gem.coop/@ns/foo/")).to be false
      end

      it "returns false for a URI with extra path segments" do
        expect(described_class.uri?("https://beta.gem.coop/@ns/foo/bar")).to be false
      end

      it "returns false for a URI missing the namespace (@-prefix)" do
        expect(described_class.uri?("https://beta.gem.coop/noat/foo")).to be false
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

    context "with a full HTTP URI including a port" do
      let(:uri) { "http://localhost:9292/@dev/test-gem" }

      it "includes the port in server_base" do
        expect(dep.server_base).to eq("http://localhost:9292")
      end

      it "sets namespace" do
        expect(dep.namespace).to eq("@dev")
      end

      it "sets gem_name" do
        expect(dep.gem_name).to eq("test-gem")
      end
    end

    context "with a gem name containing dots" do
      let(:uri) { "https://beta.gem.coop/@ns/my.gem.v2" }

      it "preserves dots in gem_name" do
        expect(dep.gem_name).to eq("my.gem.v2")
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
      it "raises ArgumentError for a plain name" do
        expect { described_class.parse("not-a-uri") }.to raise_error(ArgumentError, /Not a valid URI dependency/)
      end

      it "raises ArgumentError for an empty string" do
        expect { described_class.parse("") }.to raise_error(ArgumentError, /Not a valid URI dependency/)
      end

      it "raises ArgumentError for a URI missing namespace" do
        expect { described_class.parse("https://example.com/foo") }.to raise_error(ArgumentError)
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

  describe "#inspect" do
    it "includes the class name, gem_name, and source_url" do
      dep = described_class.parse("https://beta.gem.coop/@ns/foo")
      expect(dep.inspect).to eq('#<Namespaced::Gem::UriDependency gem_name="foo" source_url="https://beta.gem.coop/@ns">')
    end

    it "works for shorthand" do
      dep = described_class.parse("@ns/bar")
      expect(dep.inspect).to include('gem_name="bar"')
      expect(dep.inspect).to include('source_url="https://gem.coop/@ns"')
    end
  end

  describe "#== and #eql?" do
    let(:dep_a) { described_class.parse("https://beta.gem.coop/@ns/foo") }
    let(:dep_b) { described_class.parse("https://beta.gem.coop/@ns/foo") }
    let(:dep_c) { described_class.parse("https://beta.gem.coop/@ns/bar") }
    let(:dep_d) { described_class.parse("https://beta.gem.coop/@other/foo") }
    let(:dep_e) { described_class.parse("https://example.com/@ns/foo") }

    it "considers two objects with the same components equal" do
      expect(dep_a).to eq(dep_b)
    end

    it "is not equal when gem names differ" do
      expect(dep_a).not_to eq(dep_c)
    end

    it "is not equal when namespaces differ" do
      expect(dep_a).not_to eq(dep_d)
    end

    it "is not equal when servers differ" do
      expect(dep_a).not_to eq(dep_e)
    end

    it "is not equal to a non-UriDependency" do
      expect(dep_a).not_to eq("https://beta.gem.coop/@ns/foo")
    end

    it "satisfies eql? for equal objects" do
      expect(dep_a).to eql(dep_b)
    end
  end

  describe "#hash" do
    it "is the same for equal objects" do
      dep_a = described_class.parse("https://beta.gem.coop/@ns/foo")
      dep_b = described_class.parse("https://beta.gem.coop/@ns/foo")
      expect(dep_a.hash).to eq(dep_b.hash)
    end

    it "differs for different objects (generally)" do
      dep_a = described_class.parse("https://beta.gem.coop/@ns/foo")
      dep_b = described_class.parse("https://beta.gem.coop/@ns/bar")
      expect(dep_a.hash).not_to eq(dep_b.hash)
    end

    it "allows UriDependency objects to be used as hash keys" do
      dep_a = described_class.parse("https://beta.gem.coop/@ns/foo")
      dep_b = described_class.parse("https://beta.gem.coop/@ns/foo")
      hash = { dep_a => "value" }
      expect(hash[dep_b]).to eq("value")
    end

    it "allows UriDependency objects to be deduplicated in a Set" do
      require "set"
      dep_a = described_class.parse("https://beta.gem.coop/@ns/foo")
      dep_b = described_class.parse("https://beta.gem.coop/@ns/foo")
      dep_c = described_class.parse("https://beta.gem.coop/@ns/bar")
      set = Set.new([dep_a, dep_b, dep_c])
      expect(set.size).to eq(2)
    end
  end

  describe "frozen instances" do
    it "freezes the instance after initialization" do
      dep = described_class.parse("https://beta.gem.coop/@ns/foo")
      expect(dep).to be_frozen
    end

    it "freezes the string attributes" do
      dep = described_class.parse("https://beta.gem.coop/@ns/foo")
      expect(dep.original).to be_frozen
      expect(dep.server_base).to be_frozen
      expect(dep.namespace).to be_frozen
      expect(dep.gem_name).to be_frozen
    end
  end

  describe "DEFAULT_SERVER" do
    it "is https://gem.coop" do
      expect(described_class::DEFAULT_SERVER).to eq("https://gem.coop")
    end
  end
end
