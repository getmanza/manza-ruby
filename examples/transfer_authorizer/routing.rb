# frozen_string_literal: true

module TransferAuthorizer
  # Says where the API routed a new draft, from its `authorization`:
  # pending means the challenge went to the authorizer; refused, with a
  # `refusal_reason`, means it went to your in-app approvers.
  module Routing
    # The reasons a draft can be refused when it is created. The transfer
    # authorization docs' troubleshooting table has the fix for each.
    REFUSAL_REASONS = {
      "untrusted_payee" => "the payee's bank details are not trusted, and \"Approve transfers to new payees\" is off " \
                           "or their trust was revoked or they were edited",
      "unrestricted_api_key" => "the payee is new and key A has no IP allowlist",
      "over_new_payee_limit" => "the payee is new and the amount is over the limit per transfer to a new payee",
      "over_transfer_limit" => "the amount is over the limit per transfer",
      "over_daily_limit" => "this amount plus the last 24 hours' authorized total is over the limit per 24 hours",
      "currency_mismatch" => "the account's currency is not the enrolled currency",
      "suspended" => "transfer authorization is suspended, or its webhook endpoint is disabled",
      "secret_expired" => "the signing secret has expired"
    }.freeze

    module_function

    def describe(authorization)
      return "no transfer authorizer was enrolled (or the feature is off): sent to your approvers" unless authorization
      return "challenge sent, waiting for the authorizer: watch the rackup terminal" if authorization["status"] == "pending"

      reason = authorization["refusal_reason"]
      words = REFUSAL_REASONS.fetch(reason, "see the transfer authorization docs' troubleshooting table")
      "sent to your approvers, not the authorizer: #{authorization["status"]} (#{reason}), #{words}"
    end
  end
end
