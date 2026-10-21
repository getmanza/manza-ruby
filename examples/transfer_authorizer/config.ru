# frozen_string_literal: true

# The authorizer process (key B). Start it with `bundle exec rackup -p $PORT`.
require "dotenv"
Dotenv.overload(File.expand_path(".env", __dir__))
require_relative "authorizer"

$stdout.sync = true

run TransferAuthorizer::App.new(
  client: Manza.new(api_key: ENV.fetch("MANZA_AUTHORIZER_API_KEY")),
  secret: ENV.fetch("MANZA_AUTHORIZER_SECRET"),
  ledger: TransferAuthorizer::Ledger.new(File.expand_path("ledger.json", __dir__))
)
