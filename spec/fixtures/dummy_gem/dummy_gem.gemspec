# frozen_string_literal: true

Gem::Specification.new do |spec|
  spec.name    = "dummy_gem"
  spec.version = "0.0.1"
  spec.authors = ["Test"]
  spec.email   = ["test@example.com"]
  spec.summary = "A fixture gem that declares a URI dependency for integration testing."

  spec.required_ruby_version = ">= 3.2.0"

  # Traditional dependency:
  spec.add_dependency "rake", ">= 13"

  # Namespaced URI dependency — the real thing on beta.gem.coop:
  spec.add_dependency "https://beta.gem.coop/@kaspth/oaken", "~> 1.0"

  spec.files         = []
  spec.require_paths = ["lib"]
end
