# frozen_string_literal: true

require "bundler/setup"
require "dotenv"
# Use overload so MANZA_FIXTURE_* values written by `rake fixtures:seed`
# beat any stale exports lingering in the developer's shell.
Dotenv.overload
require "vcr"
require "webmock/rspec"
require "httpx"
require "httpx/adapters/webmock"
require "manza"

require_relative "support/fixture_ids"
require_relative "support/vcr"
require_relative "support/client_helpers"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
  config.include ClientHelpers
  config.include Manza::SpecFixtures
end
