# frozen_string_literal: true

module Manza
  module Resources
    # API-initiated transfers. Creating a draft never executes a
    # transfer by itself. A draft inside the entity's machine-
    # authorization envelope (trusted payee, within limits) is sent to
    # the enrolled transfer authorizer as a `payment.authorization_requested`
    # webhook; answer it with {#authorize} or {#decline}, using an API
    # key other than the one that created the draft. Every other draft
    # goes to the in-app approval flow, where a manager or legal
    # representative approves it. Poll {#get} (status: requested →
    # processing → completed / failed) or subscribe to the
    # `transfer.executed` webhook to follow execution.
    #
    # A draft's `authorization` says which way it went: `pending` (a
    # challenge was sent), `authorized`, `declined`, or `refused` /
    # `expired` / `superseded` / `failed` with a `refusal_reason` (it went
    # to the approvers): `untrusted_payee`, `unrestricted_api_key`,
    # `over_new_payee_limit`, `over_transfer_limit`, `over_daily_limit`,
    # `currency_mismatch`, `suspended`, `secret_expired`,
    # `signature_failed`, `stale` (the draft, its payee's bank details or
    # the endpoint changed while the challenge was open) or `expired`.
    # `authorization` is nil when no authorizer was enrolled.
    #
    # With "Approve transfers to new payees" on (enrolment, in the app),
    # a draft to bank details the entity never trusted is challenged too,
    # up to the new-payee limit, when the creating key has an IP
    # allowlist; authorizing it also trusts the payee.
    class TransferDrafts < Base
      # POST /api/transfer_drafts
      #
      # Required: account_id, amount, and exactly one of beneficiary_id
      # (external transfer) or destination_account_id (own-account move).
      # Optional: external_account_id, currency_code, payment_reference,
      # internal_notes, client_reference (unique per entity, at most 128
      # characters; a duplicate raises {Manza::ConflictError} whose
      # `payment_id` names the existing draft).
      def create(**attributes)
        http_post("api/transfer_drafts", body: attributes)
      end

      # GET /api/transfer_drafts/:id
      def get(id)
        http_get(encode_path("api/transfer_drafts", id))
      end

      # POST /api/transfer_drafts/:id/authorize
      #
      # Executes the draft. `authorization_id` comes from the
      # `payment.authorization_requested` webhook; build `signature` with
      # {Manza::TransferAuthorization}. Requires the `transfers:authorize`
      # scope on a key other than the draft's creator (otherwise 403
      # `same_key_forbidden`), bound to an IP allowlist (otherwise 403
      # `unrestricted_api_key`). A 409 {Manza::ConflictError} with `type`
      # `authorization_busy` means a bank-detail edit, trust or trust
      # revocation on the payee was in flight: retry. A blank signature is refused locally: the API counts
      # it as a failed attempt, and five fail the challenge.
      def authorize(id, authorization_id:, signature:)
        raise Manza::ArgumentError, "signature cannot be blank" if signature.to_s.strip.empty?

        http_post(
          encode_path("api/transfer_drafts", id, "authorize"),
          body: { authorization_id: authorization_id, signature: signature }
        )
      end

      # POST /api/transfer_drafts/:id/decline
      #
      # Declines the challenge and deletes the draft. Returns the
      # authorization (`status: "declined"`, `declined_at`, and a nil
      # `refusal_reason`).
      def decline(id, authorization_id:, reason: nil)
        http_post(
          encode_path("api/transfer_drafts", id, "decline"),
          body: { authorization_id: authorization_id, reason: reason }.compact
        )
      end
    end
  end
end
