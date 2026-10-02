# frozen_string_literal: true

module Manza
  module Resources
    # The current entity (the tenant the API key belongs to).
    #
    #   client.entity.get  # => Manza::Response
    class Entity < Base
      def get
        http_get("api/entity")
      end
    end
  end
end
