# frozen_string_literal: true

module Manza
  module Resources
    # Webhook endpoint configuration.
    class WebhookEndpoints < Base
      # GET /api/webhook_endpoints
      def list(limit: MAX_PER_PAGE, cursor: nil)
        list_page("api/webhook_endpoints", limit: limit, cursor: cursor)
      end

      # GET /api/webhook_endpoints/:id
      def get(id)
        http_get(encode_path("api/webhook_endpoints", id))
      end

      # POST /api/webhook_endpoints
      #
      # @param url [String] the URL to deliver events to
      # @param events [Array<String>] event names to subscribe to
      # @param description [String, nil]
      def create(url:, events:, description: nil)
        http_post(
          "api/webhook_endpoints",
          body: { url: url, events: events, description: description }.compact
        )
      end

      # PATCH /api/webhook_endpoints/:id
      #
      # Changing `url` on the endpoint enrolled as transfer authorizer
      # raises {Manza::ValidationError}.
      def update(id, **attributes)
        http_patch(encode_path("api/webhook_endpoints", id), body: attributes)
      end

      # DELETE /api/webhook_endpoints/:id
      #
      # A soft delete (still 204).
      def delete(id)
        http_delete(encode_path("api/webhook_endpoints", id))
      end

      # POST /api/webhook_endpoints/:id/test
      def test_endpoint(id)
        http_post(encode_path("api/webhook_endpoints", id, "test"))
      end

      # POST /api/webhook_endpoints/:id/regenerate_secret
      #
      # Raises {Manza::ValidationError} on the enrolled transfer authorizer.
      def regenerate_secret(id)
        http_post(encode_path("api/webhook_endpoints", id, "regenerate_secret"))
      end

      # POST /api/webhook_endpoints/:id/enable
      def enable(id)
        http_post(encode_path("api/webhook_endpoints", id, "enable"))
      end

      # POST /api/webhook_endpoints/:id/disable
      def disable(id)
        http_post(encode_path("api/webhook_endpoints", id, "disable"))
      end
    end
  end
end
