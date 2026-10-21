# frozen_string_literal: true

# The creator process (key A). Creates a transfer draft, writes it to the
# ledger from the API's response, and says where the API routed it.
#
#   bundle exec ruby create_transfer.rb          # 10.00
#   bundle exec ruby create_transfer.rb 250.00
require "dotenv"
Dotenv.overload(File.expand_path(".env", __dir__))
require "securerandom"
require "manza"
require_relative "ledger"

amount = ARGV.fetch(0, "10.00")
client_reference = "example-#{SecureRandom.hex(6)}"
ledger = TransferAuthorizer::Ledger.new(File.expand_path("ledger.json", __dir__))
creator = Manza.new(api_key: ENV.fetch("MANZA_CREATOR_API_KEY"))

begin
  draft = creator.transfer_drafts.create(
    account_id: ENV.fetch("MANZA_ACCOUNT_ID"),
    beneficiary_id: ENV.fetch("MANZA_BENEFICIARY_ID"),
    amount: amount,
    payment_reference: "Transfer authorizer example",
    client_reference: client_reference
  ).body
rescue Manza::Error => e
  abort "create failed: #{e.class.name}: #{e.message} (type #{e.type.inspect}, request_id #{e.request_id.inspect})"
end

begin
  payee = Manza::TransferAuthorization.payee_for(
    external_account_id: draft["destination_account_id"] ? nil : draft["external_account_id"],
    destination_account_id: draft["destination_account_id"]
  )
rescue Manza::ArgumentError
  abort "payment #{draft["id"]} names neither an external_account_id nor a destination_account_id, so it was not " \
        "written to the ledger: the authorizer will decline it"
end
ledger.record(
  client_reference,
  payment_id: draft["id"], amount: draft["amount"], currency_code: draft["currency_code"],
  account_id: draft["account_id"], payee: payee
)
puts "created payment #{draft["id"]}: #{draft["amount"]} #{draft["currency_code"]} to #{payee} (client_reference #{client_reference})"

if draft["authorization"]
  puts "challenge sent, waiting for the authorizer: watch the rackup terminal"
else
  puts "sent to your approvers, not the authorizer: see Troubleshooting in README.md"
end
