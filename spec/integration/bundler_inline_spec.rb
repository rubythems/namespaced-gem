# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"

RSpec.describe "bundler/inline with URI dependencies", :network do
  let(:namespaced_gem_lib) { File.expand_path("../../lib", __dir__) }

  # Build a clean environment following the appraisal2 pattern.
  def clean_env
    env = if Bundler.respond_to?(:original_env)
      Bundler.original_env.to_h
    else
      ENV.to_h
    end

    if env["RUBYOPT"]
      parts = env["RUBYOPT"].split(" ")
      parts.reject! { |opt| opt == "-rbundler/setup" || opt.include?("bundler/setup") }
      env["RUBYOPT"] = parts.empty? ? nil : parts.join(" ")
    end

    %w[
      BUNDLER_SETUP
      BUNDLER_VERSION
      BUNDLE_BIN_PATH
      BUNDLE_GEMFILE
      BUNDLE_LOCKFILE
      BUNDLE_PATH
    ].each { |k| env.delete(k) }

    env
  end

  it "resolves and loads oaken via a URI dependency in an inline Gemfile" do
    Dir.mktmpdir("namespaced_gem_inline") do |tmpdir|
      script_path = File.join(tmpdir, "inline_test.rb")
      File.write(script_path, <<~RUBY)
        require "rubygems"
        $LOAD_PATH.unshift(#{namespaced_gem_lib.inspect})
        require "rubygems_plugin"

        require "bundler/inline"

        gemfile(true) do
          source "https://rubygems.org"

          source "https://beta.gem.coop/@kaspth" do
            gem "oaken", "~> 1.0", require: false
          end
        end

        # Resolution + install succeeded. Print the version.
        oaken_spec = Gem.loaded_specs["oaken"] || Bundler.definition.specs.find { |s| s.name == "oaken" }
        $stdout.puts "oaken_resolved=\#{oaken_spec.version}" if oaken_spec
      RUBY

      stdout, stderr, status = Open3.capture3(
        clean_env,
        "ruby", "--disable-gems", script_path,
        chdir: Dir.tmpdir,
      )

      aggregate_failures "bundler/inline should resolve oaken" do
        expect(status.success?).to be(true), -> {
          "Script failed.\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
        }
        expect(stdout).to match(/oaken_resolved=1\./)
      end
    end
  end
end
