# frozen_string_literal: true

module Manza
  module Resources
    # Accounts and their transactions.
    class Accounts < Base
      # GET /api/accounts
      #
      # @param status [String, nil] filter by account status
      # @param currency_code [String, nil] e.g. "MAD" or "ZAR"
      # @param limit [Integer] page size (max 100)
      # @param cursor [String, nil] pagination cursor
      # @return [Manza::Page]
      def list(status: nil, currency_code: nil, limit: MAX_PER_PAGE, cursor: nil)
        list_page(
          "api/accounts",
          status: status,
          currency_code: currency_code,
          limit: limit,
          cursor: cursor
        )
      end

      # GET /api/accounts/:id
      def get(id)
        http_get(encode_path("api/accounts", id))
      end

      # GET /api/accounts/:account_id/transactions
      #
      # @param operation [String, nil] filter by movement operation
      # @param posted_after [String, Time, nil] ISO-8601 timestamp lower bound
      # @param posted_before [String, Time, nil] ISO-8601 timestamp upper bound
      def list_transactions(account_id, operation: nil, posted_after: nil, posted_before: nil, limit: MAX_PER_PAGE,
                            cursor: nil)
        list_page(
          encode_path("api/accounts", account_id, "transactions"),
          operation: operation,
          posted_after: serialize_time(posted_after),
          posted_before: serialize_time(posted_before),
          limit: limit,
          cursor: cursor
        )
      end

      # GET /api/accounts/:account_id/transactions/:id
      def get_transaction(account_id, transaction_id)
        http_get(encode_path("api/accounts", account_id, "transactions", transaction_id))
      end

      private

      def serialize_time(value)
        return nil if value.nil?
        return value if value.is_a?(String)

        value.iso8601
      end
    end
  end
end
