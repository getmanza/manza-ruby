# frozen_string_literal: true

module Zazu
  module Resources
    # Saved transfer recipients. Each beneficiary embeds its bank
    # accounts; the one flagged `default` is used when a transfer names
    # only the beneficiary_id. There is no update or delete via the API.
    class Beneficiaries < Base
      # GET /api/beneficiaries
      def list(limit: MAX_PER_PAGE, cursor: nil)
        list_page("api/beneficiaries", limit: limit, cursor: cursor)
      end

      # GET /api/beneficiaries/:id
      def get(id)
        http_get(encode_path("api/beneficiaries", id))
      end

      # POST /api/beneficiaries
      #
      # Keys: beneficiary_type, person_name, company_name, email,
      # phone_number. Values must be strings. Shares a 10/minute limit
      # with {#create_external_account}.
      def create(**attributes)
        http_post("api/beneficiaries", body: attributes)
      end

      # GET /api/beneficiaries/:beneficiary_id/external_accounts
      def list_external_accounts(beneficiary_id, limit: MAX_PER_PAGE, cursor: nil)
        list_page(encode_path("api/beneficiaries", beneficiary_id, "external_accounts"), limit: limit, cursor: cursor)
      end

      # GET /api/beneficiaries/:beneficiary_id/external_accounts/:id
      def get_external_account(beneficiary_id, id)
        http_get(encode_path("api/beneficiaries", beneficiary_id, "external_accounts", id))
      end

      # POST /api/beneficiaries/:beneficiary_id/external_accounts
      #
      # Required: account_number. Optional: name, country_code,
      # currency_code, account_type ("bank" only), bank_identifier
      # (required in ZA, rejected in MA, where it is derived from the RIB).
      def create_external_account(beneficiary_id, **attributes)
        http_post(encode_path("api/beneficiaries", beneficiary_id, "external_accounts"), body: attributes)
      end
    end
  end
end
