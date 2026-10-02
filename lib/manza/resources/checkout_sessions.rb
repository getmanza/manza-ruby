# frozen_string_literal: true

module Manza
  module Resources
    # One-off hosted checkout sessions. Pre-API there's no list,
    # update, or delete — sessions are created and inspected by id.
    # State (`open`, `processing`, `clearing`, `complete`, `expired`)
    # transitions are read-only from the SDK's perspective. Responses
    # carry `settled_at` and the paying `transaction`.
    class CheckoutSessions < Base
      # GET /api/checkout_sessions/:id
      def get(id)
        http_get(encode_path("api/checkout_sessions", id))
      end

      # POST /api/checkout_sessions
      #
      # @param attributes [Hash] checkout-session attributes — see API docs.
      #   Required: account_id, amount, success_url.
      #   Optional: metadata, customer_email, customer_name, cancel_url,
      #   description, expires_at, collect_billing_address, billing_address.
      def create(**attributes)
        http_post("api/checkout_sessions", body: attributes)
      end
    end
  end
end
