# frozen_string_literal: true

# Ruby SDK for the Manza API.
#
# Usage:
#
#   manza = Manza.new(api_key: ENV["MANZA_API_KEY"])
#   manza.entity.get
#   manza.accounts.list(limit: 50)
#
# See README.md for full documentation.
module Manza
  # Module-level shortcut. Equivalent to Manza::Client.new(...).
  def self.new(**)
    Client.new(**)
  end
end

require_relative "manza/version"
require_relative "manza/errors"
require_relative "manza/response"
require_relative "manza/page"
require_relative "manza/transfer_authorization"
require_relative "manza/resources/base"
require_relative "manza/resources/accounts"
require_relative "manza/resources/beneficiaries"
require_relative "manza/resources/checkout_sessions"
require_relative "manza/resources/customers"
require_relative "manza/resources/entity"
require_relative "manza/resources/invoices"
require_relative "manza/resources/payee_trust_requests"
require_relative "manza/resources/payment_links"
require_relative "manza/resources/transfer_drafts"
require_relative "manza/resources/webhook_endpoints"
require_relative "manza/client"
