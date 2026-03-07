# frozen_string_literal: true

require "tmpdir"
require "fileutils"
require "open3"

# Integration tests that verify the full bundle-lock flow against the real
# beta.gem.coop server.  They exercise the same code path a user would hit
# when their gemspec declares a URI dependency and they run `bundle lock`.
#
# Environment isolation follows the pattern proven in appraisal2:
#   1. Capture Bundler.original_env (pre-`bundle exec` state).
#   2. Strip `-rbundler/setup` from RUBYOPT so the subprocess boots clean.
#   3. Delete BUNDLER_SETUP / BUNDLER_VERSION activation markers.
#   4. Point BUNDLE_GEMFILE / BUNDLE_APP_CONFIG at the temp directory.
#   5. Run `ruby --disable-gems <script>` so our plugin loads before Bundler.
RSpec.describe "bundle lock with URI dependencies", :network do
  let(:namespaced_gem_lib) { File.expand_path("../../lib", __dir__) }
  let(:fixture_gemspec) { File.expand_path("../fixtures/dummy_gem/dummy_gem.gemspec", __dir__) }

  around do |example|
    Dir.mktmpdir("namespaced_gem_integration") do |tmpdir|
      @tmpdir = tmpdir
      example.run
    end
  end

  def write_file(name, content)
    path = File.join(@tmpdir, name)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  # Build a clean environment hash following the appraisal2 pattern:
  # start from Bundler.original_env, strip bundler activation, then point
  # everything at our temp directory.
  def clean_env
    env = if Bundler.respond_to?(:original_env)
      Bundler.original_env.to_h
    else
      ENV.to_h
    end

    # Strip bundler/setup from RUBYOPT so the subprocess doesn't auto-activate
    if env["RUBYOPT"]
      parts = env["RUBYOPT"].split(" ")
      parts.reject! { |opt| opt == "-rbundler/setup" || opt.include?("bundler/setup") }
      env["RUBYOPT"] = parts.empty? ? nil : parts.join(" ")
    end

    # Remove bundler activation markers
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

  # Run a Ruby script with --disable-gems so we control the exact load order.
  # This mirrors what happens when namespaced-gem is *installed* as a real gem:
  # RubyGems loads rubygems_plugin.rb at boot, BEFORE Bundler evaluates any
  # gemspec.  Using --disable-gems + explicit require simulates that without
  # needing `gem install`.
  def run_bundle_lock
    gemfile_path = File.join(@tmpdir, "Gemfile")
    lockfile_path = File.join(@tmpdir, "Gemfile.lock")

    write_file("run_lock.rb", <<~RUBY)
      require "rubygems"

      $LOAD_PATH.unshift(#{namespaced_gem_lib.inspect})
      require "rubygems_plugin"

      ENV["BUNDLE_GEMFILE"] = #{gemfile_path.inspect}
      ENV["BUNDLE_LOCKFILE"] = #{lockfile_path.inspect}
      ENV["BUNDLE_APP_CONFIG"] = #{File.join(@tmpdir, ".bundle").inspect}

      require "bundler"
      Bundler.reset!

      definition = Bundler.definition(true)
      definition.resolve_remotely!
      definition.lock
      $stdout.puts "lock_ok"
    RUBY

    FileUtils.mkdir_p(File.join(@tmpdir, ".bundle"))

    Open3.capture3(
      clean_env,
      "ruby", "--disable-gems", File.join(@tmpdir, "run_lock.rb"),
      # Run from a neutral directory — NOT @tmpdir (which has a Gemfile).
      # RubyGems auto-detects Gemfiles in cwd and would load bundler/setup
      # before our plugin gets a chance to patch anything.
      chdir: Dir.tmpdir,
    )
  end

  describe "with a gemspec that declares a URI dep on @kaspth/oaken" do
    before do
      FileUtils.cp(fixture_gemspec, File.join(@tmpdir, "dummy_gem.gemspec"))

      write_file("Gemfile", <<~GEMFILE)
        source "https://rubygems.org"
        gemspec
      GEMFILE
    end

    it "resolves successfully and produces a Gemfile.lock" do
      stdout, stderr, status = run_bundle_lock

      aggregate_failures "bundle lock should succeed" do
        expect(status.success?).to be(true), -> {
          "bundle lock failed.\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
        }
        expect(File.exist?(File.join(@tmpdir, "Gemfile.lock"))).to be true
      end
    end

    it "records oaken under the beta.gem.coop/@kaspth source in the lockfile" do
      stdout, stderr, status = run_bundle_lock
      expect(status.success?).to be(true), -> {
        "bundle lock failed.\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
      }

      lockfile = File.read(File.join(@tmpdir, "Gemfile.lock"))

      aggregate_failures "lockfile content" do
        expect(lockfile).to include("https://beta.gem.coop/@kaspth")
        expect(lockfile).to match(/^\s+oaken\b/)
      end
    end

    it "records the correct version of oaken" do
      stdout, stderr, status = run_bundle_lock
      expect(status.success?).to be(true), -> {
        "bundle lock failed.\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
      }

      lockfile = File.read(File.join(@tmpdir, "Gemfile.lock"))

      expect(lockfile).to match(/oaken \(1\./)
    end

    it "also records the traditional rubygems.org source" do
      stdout, stderr, status = run_bundle_lock
      expect(status.success?).to be(true), -> {
        "bundle lock failed.\nSTDOUT: #{stdout}\nSTDERR: #{stderr}"
      }

      lockfile = File.read(File.join(@tmpdir, "Gemfile.lock"))

      expect(lockfile).to include("https://rubygems.org")
    end
  end
end
