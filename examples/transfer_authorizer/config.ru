# frozen_string_literal: true

# The authorizer process (key B). Start it with `bundle exec rackup -p 4599`
# (rackup reads -p before this file loads .env, so PORT in .env does not set it).
require "dotenv"
Dotenv.overload(File.expand_path(".env", __dir__))
require_relative "authorizer"

$stdout.sync = true

missing = %w[MANZA_AUTHORIZER_API_KEY MANZA_AUTHORIZER_SECRET].select { |name| ENV.fetch(name, "").empty? }
abort "Set #{missing.join(" and ")} in #{File.expand_path(".env", __dir__)}" unless missing.empty?

run TransferAuthorizer::App.new(
  client: Manza.new(api_key: ENV.fetch("MANZA_AUTHORIZER_API_KEY")),
  secret: ENV.fetch("MANZA_AUTHORIZER_SECRET"),
  ledger: TransferAuthorizer::Ledger.new(File.expand_path("ledger.json", __dir__))
)
