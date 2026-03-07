# frozen_string_literal: true

RSpec.describe Namespaced::Gem::GemResolverPatch do
  before do
    Namespaced::Gem::DependencyPatch.apply!
    described_class.apply!
  end

  describe ".apply!" do
    it "is idempotent" do
      expect { described_class.apply! }.not_to raise_error
    end

    it "prepends RequestSetPatch onto Gem::RequestSet" do
      expect(::Gem::RequestSet.ancestors).to include(described_class::RequestSetPatch)
    end

    it "prepends InstallerSetPatch onto Gem::Resolver::InstallerSet" do
      expect(::Gem::Resolver::InstallerSet.ancestors).to include(described_class::InstallerSetPatch)
    end
  end

  describe "InstallerSetPatch#find_all" do
    # Build installer_set BEFORE any Gem::Source.new stubs are active, since
    # InstallerSet#initialize calls Gem::Source.new internally.
    let!(:installer_set) { ::Gem::Resolver::InstallerSet.new(:both) }

    context "with a plain (non-URI) dep" do
      it "does not intercept the request (delegates straight to super)" do
        dep = ::Gem::Dependency.new("rack", ">= 0")
        req = ::Gem::Resolver::DependencyRequest.new(dep, nil)

        # Our patch should return early and not touch Gem::Source for non-URI names
        allow(::Gem::Source).to receive(:new).and_call_original

        begin
          installer_set.find_all(req)
        rescue StandardError
          nil
        end

        # Verify ::Gem::Source.new was NOT called with a plain gem name
        expect(::Gem::Source).not_to have_received(:new).with("rack")
      end
    end

    context "with a URI dep" do
      let(:uri) { "https://beta.gem.coop/@pboling/foo" }

      # Allow Gem::Source.new for other args (fallback), expect it for our namespace URL.
      before { allow(::Gem::Source).to receive(:new).and_call_original }

      it "creates a Gem::Source for the namespace source URL" do
        dep = ::Gem::Dependency.new(uri, "~> 1.0")
        req = ::Gem::Resolver::DependencyRequest.new(dep, nil)

        src_double = instance_double(::Gem::Source)
        rset_double = double("resolver_set", find_all: [])

        expect(::Gem::Source).to receive(:new)
          .with("https://beta.gem.coop/@pboling")
          .and_return(src_double)
        allow(src_double).to receive(:dependency_resolver_set).and_return(rset_double)

        installer_set.find_all(req)
      end

      it "passes a remapped DependencyRequest with the real gem name" do
        dep = ::Gem::Dependency.new(uri, "~> 2.0")
        req = ::Gem::Resolver::DependencyRequest.new(dep, nil)

        received_req = nil
        src_double = instance_double(::Gem::Source)
        rset_double = double("resolver_set")
        allow(rset_double).to receive(:find_all) { |r| received_req = r; [] }

        allow(::Gem::Source).to receive(:new)
          .with("https://beta.gem.coop/@pboling")
          .and_return(src_double)
        allow(src_double).to receive(:dependency_resolver_set).and_return(rset_double)

        installer_set.find_all(req)

        expect(received_req).not_to be_nil
        expect(received_req.name).to eq("foo")
        expect(received_req.dependency.requirement.as_list).to eq(["~> 2.0"])
      end
    end
  end

  describe "RequestSetPatch#resolve" do
    let(:uri) { "https://beta.gem.coop/@pboling/foo" }

    # The resolver set must respond to the interface Gem::RequestSet#resolve calls.
    def stub_resolver_set_for(source_url)
      src_double = instance_double(::Gem::Source)
      rset_double = double("resolver_set")
      allow(rset_double).to receive(:remote=)
      allow(rset_double).to receive(:prerelease=)
      allow(rset_double).to receive(:find_all).and_return([])
      allow(rset_double).to receive(:prefetch)
      allow(rset_double).to receive(:errors).and_return([])
      # Allow Gem::Source.new for anything (BestSet internals call it too).
      allow(::Gem::Source).to receive(:new).and_call_original
      allow(::Gem::Source).to receive(:new).with(source_url).and_return(src_double)
      allow(src_double).to receive(:dependency_resolver_set).and_return(rset_double)
      rset_double
    end

    context "with a URI dep" do
      it "remaps the URI dep to the real gem name in @dependencies" do
        rset = stub_resolver_set_for("https://beta.gem.coop/@pboling")
        request_set = ::Gem::RequestSet.new(::Gem::Dependency.new(uri, "~> 1.0"))

        begin
          request_set.resolve
        rescue StandardError
          nil
        end

        dep_names = request_set.instance_variable_get(:@dependencies).map(&:name)
        expect(dep_names).to eq(["foo"])
      end

      it "prepends the namespace resolver set to @sets" do
        rset = stub_resolver_set_for("https://beta.gem.coop/@pboling")
        request_set = ::Gem::RequestSet.new(::Gem::Dependency.new(uri, "~> 1.0"))

        begin
          request_set.resolve
        rescue StandardError
          nil
        end

        sets = request_set.instance_variable_get(:@sets)
        expect(sets).to include(rset)
      end
    end

    context "with a plain (non-URI) dep" do
      it "leaves @dependencies unchanged" do
        request_set = ::Gem::RequestSet.new(::Gem::Dependency.new("rack", ">= 2.0"))

        begin
          request_set.resolve
        rescue StandardError
          nil
        end

        dep_names = request_set.instance_variable_get(:@dependencies).map(&:name)
        expect(dep_names).to include("rack")
      end
    end
  end
end
