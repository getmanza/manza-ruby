# frozen_string_literal: true

module Zazu
  module Resources
    # Customers — individuals or businesses the entity invoices.
    class Customers < Base
      # GET /api/customers
      #
      # @param q [String, nil] search query (matches company name, person name, email)
      def list(q: nil, limit: MAX_PER_PAGE, cursor: nil)
        list_page("api/customers", q: q, limit: limit, cursor: cursor)
      end

      # GET /api/customers/:id
      def get(id)
        http_get(encode_path("api/customers", id))
      end

      # POST /api/customers
      #
      # @param attributes [Hash] customer attributes — see API docs.
      #   Common keys: customer_type ("individual"|"business"),
      #   person_name, company_name, email, phone, registration_number,
      #   vat_number, billing_address (Hash with street/city/postal_code/
      #   country/country_code). Morocco only: tax_id, ice_number — these
      #   keys are absent from responses in other markets.
      def create(**attributes)
        http_post("api/customers", body: attributes)
      end

      # PATCH /api/customers/:id
      def update(id, **attributes)
        http_patch(encode_path("api/customers", id), body: attributes)
      end

      # DELETE /api/customers/:id
      def delete(id)
        http_delete(encode_path("api/customers", id))
      end
    end
  end
end
