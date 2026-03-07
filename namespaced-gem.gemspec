# frozen_string_literal: true

require_relative "lib/namespaced/gem/version"

Gem::Specification.new do |spec|
  spec.name = "namespaced-gem"
  spec.version = Namespaced::Gem::VERSION
  spec.authors = ["Peter H. Boling"]
  spec.email = ["peter.boling@gmail.com"]

  spec.summary = "RubyGems plugin enabling URI-style gemspec dependencies for namespaced gem sources (e.g. gem.coop namespaces)."
  spec.description = <<~DESC
    A RubyGems plugin that allows gemspec dependencies to be declared as full
    URIs pointing to namespaced gem sources such as gem.coop namespaces
    (e.g. `https://beta.gem.coop/@myspace/my-gem`).

    When installed, this gem patches Gem::Dependency to accept URI-style names
    and patches Bundler::Dsl to automatically inject the correct `source` blocks
    when processing gemspecs — so the consuming project's Gemfile needs no
    manual source declarations for URI-specified dependencies.

    See https://github.com/gem-coop/gem.coop/issues/12 for the original discussion.
  DESC
  spec.homepage = "https://gitlab.com/galtzo-floss/namespaced-gem"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"
  spec.required_rubygems_version = ">= 4.0.5"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/-/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore .rspec spec/ .gitlab-ci.yml .rubocop.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]
end
