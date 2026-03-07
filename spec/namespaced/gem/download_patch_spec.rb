# frozen_string_literal: true

require "rubygems/remote_fetcher"

RSpec.describe Namespaced::Gem::DownloadPatch do
  before do
    described_class.apply!
  end

  after do
    Namespaced::Gem::NamespaceSourceRegistry.clear!
  end

  describe ".apply!" do
    it "is idempotent" do
      expect { described_class.apply! }.not_to raise_error
    end

    it "prepends SourceDownloadPatch onto Gem::Source" do
      expect(::Gem::Source.ancestors).to include(described_class::SourceDownloadPatch)
    end

    it "sets the patched flag" do
      expect(::Gem::Source.instance_variable_get(:@namespaced_gem_download_patched)).to be true
    end
  end

  describe "SourceDownloadPatch#download" do
    let(:namespace_source_url) { "https://beta.gem.coop/@kaspth/" }
    let(:source) { ::Gem::Source.new(namespace_source_url) }

    let(:spec) do
      s = ::Gem::Specification.new
      s.name = "oaken"
      s.version = "2.5.1"
      s.platform = "ruby"
      s.authors = ["test"]
      s.summary = "test"
      s
    end

    context "when the source IS a registered namespace source" do
      before do
        Namespaced::Gem::NamespaceSourceRegistry.register(namespace_source_url)
      end

      context "and the download succeeds" do
        it "delegates to the original download (super)" do
          # Stub the fetcher so it doesn't actually hit the network.
          fetcher = instance_double(Gem::RemoteFetcher)
          allow(Gem::RemoteFetcher).to receive(:fetcher).and_return(fetcher)
          allow(fetcher).to receive(:download).and_return("/tmp/cache/oaken-2.5.1.gem")

          result = source.download(spec, Dir.pwd)
          expect(result).to eq("/tmp/cache/oaken-2.5.1.gem")
        end
      end

      context "and the download fails with FetchError" do
        it "raises Namespaced::Gem::Error with a clear message" do
          fetcher = instance_double(Gem::RemoteFetcher)
          allow(Gem::RemoteFetcher).to receive(:fetcher).and_return(fetcher)
          allow(fetcher).to receive(:download).and_raise(
            Gem::RemoteFetcher::FetchError.new("404 Not Found", "https://beta.gem.coop/@kaspth/gems/oaken-2.5.1.gem")
          )
          allow(Gem).to receive(:ensure_gem_subdirectories)

          expect { source.download(spec, Dir.pwd) }.to raise_error(
            Namespaced::Gem::Error
          ) do |error|
            expect(error.message).to include("oaken-2.5.1.gem")
            expect(error.message).to include("namespace source")
            expect(error.message).to include("beta.gem.coop/@kaspth")
            expect(error.message).to include("CANNOT be stripped")
            expect(error.message).to include("server-side requirement")
          end
        end

        it "does NOT fall back to the root server or rubygems.org" do
          fetcher = instance_double(Gem::RemoteFetcher)
          allow(Gem::RemoteFetcher).to receive(:fetcher).and_return(fetcher)
          allow(fetcher).to receive(:download).and_raise(
            Gem::RemoteFetcher::FetchError.new("404 Not Found", "https://beta.gem.coop/@kaspth/gems/oaken-2.5.1.gem")
          )
          allow(Gem).to receive(:ensure_gem_subdirectories)

          # It should raise, not silently succeed with a different source.
          expect { source.download(spec, Dir.pwd) }.to raise_error(Namespaced::Gem::Error)

          # Verify the fetcher was only called once (no retry with a different URL).
          expect(fetcher).to have_received(:download).once
        end
      end
    end

    context "when the source is NOT a registered namespace source" do
      context "and the download fails with FetchError" do
        it "re-raises the original FetchError (no wrapping)" do
          non_ns_source = ::Gem::Source.new("https://rubygems.org")

          fetcher = instance_double(Gem::RemoteFetcher)
          allow(Gem::RemoteFetcher).to receive(:fetcher).and_return(fetcher)
          allow(fetcher).to receive(:download).and_raise(
            Gem::RemoteFetcher::FetchError.new("404 Not Found", "https://rubygems.org/gems/oaken-2.5.1.gem")
          )
          allow(Gem).to receive(:ensure_gem_subdirectories)

          expect { non_ns_source.download(spec, Dir.pwd) }.to raise_error(
            Gem::RemoteFetcher::FetchError,
            /404 Not Found/
          )
        end
      end
    end
  end
end
