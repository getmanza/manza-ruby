# frozen_string_literal: true

require "openssl"

module Manza
  # Signs a machine-authorization challenge for an API-created transfer
  # draft. Pure functions — no HTTP.
  #
  # The `payment.authorization_requested` webhook delivers the
  # authorization id and a one-time nonce. Build the signature input
  # from your *own* record of the transfer (not the webhook's
  # `signature_input`, which is there only to compare against), sign
  # it with the authorizer endpoint's signing secret, and pass the
  # result to {Resources::TransferDrafts#authorize}:
  #
  #   input = Manza::TransferAuthorization.signature_input(
  #     payment_id: draft["id"], nonce: nonce, amount: draft["amount"],
  #     currency_code: draft["currency_code"], account_id: draft["account_id"],
  #     payee: Manza::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"]),
  #     client_reference: draft["client_reference"]
  #   )
  #   signature = Manza::TransferAuthorization.sign(secret: signing_secret, signature_input: input)
  #   manza.transfer_drafts.authorize(draft["id"], authorization_id: authorization_id, signature: signature)
  module TransferAuthorization
    SIGNATURE_VERSION = "manza.transfer-authorization.v1"

    module_function

    # `amount` must be the API's decimal string verbatim (e.g. "2500.0").
    # `client_reference` is empty when the transfer has none.
    def signature_input(payment_id:, nonce:, amount:, currency_code:, account_id:, payee:, client_reference: nil)
      raise Manza::ArgumentError, "amount must be the API's decimal string (got #{amount.inspect})" unless amount.is_a?(String)

      [
        SIGNATURE_VERSION, payment_id, nonce, amount, currency_code, account_id, payee, client_reference.to_s
      ].join("|")
    end

    # Hex HMAC-SHA256 of the signature input under the authorizer
    # endpoint's signing secret.
    def sign(secret:, signature_input:)
      OpenSSL::HMAC.hexdigest("SHA256", secret, signature_input)
    end

    # The payee token: `ext:<id>` for a beneficiary's bank account,
    # `own:<id>` for one of the entity's own accounts. Pass exactly one.
    def payee_for(external_account_id: nil, destination_account_id: nil)
      unless external_account_id.nil? ^ destination_account_id.nil?
        raise Manza::ArgumentError, "pass exactly one of external_account_id or destination_account_id"
      end

      destination_account_id ? "own:#{destination_account_id}" : "ext:#{external_account_id}"
    end
  end
end
