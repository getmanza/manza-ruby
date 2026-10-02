# frozen_string_literal: true

# Ruby SDK for the Zazu API.
#
# Usage:
#
#   zazu = Zazu.new(api_key: ENV["ZAZU_API_KEY"])
#   zazu.entity.get
#   zazu.accounts.list(limit: 50)
#
# See README.md for full documentation.
module Zazu
  # Module-level shortcut. Equivalent to Zazu::Client.new(...).
  def self.new(**)
    Client.new(**)
  end
end

require_relative "zazu/version"
require_relative "zazu/errors"
require_relative "zazu/response"
require_relative "zazu/page"
require_relative "zazu/transfer_authorization"
require_relative "zazu/resources/base"
require_relative "zazu/resources/accounts"
require_relative "zazu/resources/beneficiaries"
require_relative "zazu/resources/checkout_sessions"
require_relative "zazu/resources/customers"
require_relative "zazu/resources/entity"
require_relative "zazu/resources/invoices"
require_relative "zazu/resources/payee_trust_requests"
require_relative "zazu/resources/payment_links"
require_relative "zazu/resources/transfer_drafts"
require_relative "zazu/resources/webhook_endpoints"
require_relative "zazu/client"
