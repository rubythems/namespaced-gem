# frozen_string_literal: true

require "bundler"
require "bundler/dsl"
require "namespaced/gem"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Integration tests that hit the network are tagged :network.
  # Exclude them by default; opt-in with: bundle exec rspec --tag network
  config.filter_run_excluding :network unless config.inclusion_filter[:network]
end
