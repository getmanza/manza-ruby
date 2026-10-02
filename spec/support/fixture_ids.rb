# frozen_string_literal: true

# Canonical mapping of fixture env vars → cassette placeholders.
#
# When recording, VCR scrubs `ENV[env_var]` to the placeholder before
# writing the cassette. When replaying, specs call `fixture_id(env_var)`
# which returns the placeholder when the env var is unset (CI) or the
# real ID when it is set (a developer recording a fresh cassette).
#
# Both halves use the same table so they can never drift.
module Manza
  module SpecFixtures
    IDS = {
      "MANZA_FIXTURE_ACCOUNT_ID" => "fixture-account-id",
      "MANZA_FIXTURE_TRANSACTION_ID" => "fixture-transaction-id",
      "MANZA_FIXTURE_CUSTOMER_ID" => "fixture-customer-id",
      "MANZA_FIXTURE_DELETABLE_CUSTOMER_ID" => "fixture-deletable-customer-id",
      "MANZA_FIXTURE_INVOICE_ID" => "fixture-invoice-id",
      "MANZA_FIXTURE_DELETABLE_INVOICE_ID" => "fixture-deletable-invoice-id",
      "MANZA_FIXTURE_PAYMENT_LINK_ID" => "fixture-payment-link-id",
      "MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID" => "fixture-cancellable-payment-link-id",
      "MANZA_FIXTURE_WEBHOOK_ID" => "fixture-webhook-id",
      "MANZA_FIXTURE_ENABLED_WEBHOOK_ID" => "fixture-enabled-webhook-id",
      "MANZA_FIXTURE_DISABLED_WEBHOOK_ID" => "fixture-disabled-webhook-id",
      "MANZA_FIXTURE_DELETABLE_WEBHOOK_ID" => "fixture-deletable-webhook-id",
      "MANZA_FIXTURE_CHECKOUT_SESSION_ID" => "fixture-checkout-session-id",
      "MANZA_FIXTURE_BENEFICIARY_ID" => "fixture-beneficiary-id",
      "MANZA_FIXTURE_TRANSFER_DRAFT_ID" => "fixture-transfer-draft-id",
      # The discovered beneficiary's default bank account, marked a
      # trusted payee once by hand so machine-authorized drafts can
      # target it.
      "MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID" => "fixture-trusted-external-account-id",
      "MANZA_FIXTURE_CREATED_BENEFICIARY_ID" => "fixture-created-beneficiary-id",
      "MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID" => "fixture-external-account-id",
      # Not an ID, but fresh per seed (bank account numbers are unique
      # per entity) and scrubbed the same way.
      "MANZA_FIXTURE_NEW_ACCOUNT_NUMBER" => "fixture-new-account-number",
      "MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID" => "fixture-payee-trust-request-id",
      # client_reference is unique per entity, so these are fresh per seed too.
      "MANZA_FIXTURE_CLIENT_REFERENCE" => "fixture-client-reference",
      "MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE" => "fixture-authorizable-client-reference",
      "MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID" => "fixture-authorizable-draft-id",
      "MANZA_FIXTURE_DECLINABLE_DRAFT_ID" => "fixture-declinable-draft-id",
      "MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID" => "fixture-bad-signature-draft-id",
      "MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID" => "fixture-authorizable-authorization-id",
      "MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID" => "fixture-declinable-authorization-id",
      "MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID" => "fixture-bad-signature-authorization-id",
      # One-time nonce from the authorization webhook. Only needed while
      # recording; it never appears in a request or response.
      "MANZA_FIXTURE_AUTHORIZABLE_NONCE" => "fixture-authorizable-nonce"
    }.freeze

    def fixture_id(env_var)
      placeholder = IDS.fetch(env_var) do
        raise ArgumentError, "Unknown fixture env var: #{env_var}. Add it to Manza::SpecFixtures::IDS."
      end

      ENV.fetch(env_var, placeholder)
    end

    module_function :fixture_id
  end
end
