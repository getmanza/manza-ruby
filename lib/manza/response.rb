# frozen_string_literal: true

module Manza
  # Wraps a Faraday response with the few helpers callers actually
  # want. Cheap value object — no parsing or normalization is done
  # eagerly; `body`, `data`, `headers` all read straight through.
  #
  # The SDK's resource methods return one of these directly when the
  # endpoint is a single-record fetch. List endpoints return a
  # {Manza::Page} instead, which composes a Response.
  class Response
    attr_reader :raw, :request_id

    def initialize(raw, request_id: nil)
      @raw = raw
      @request_id = request_id || raw.headers["x-request-id"]
    end

    def status
      raw.status
    end

    def headers
      raw.headers
    end

    def body
      raw.body
    end

    def success?
      status.between?(200, 299)
    end

    # Returns the response body without the `data` envelope when one
    # is present. List endpoints wrap their items in `{"data": [...]}`
    # — this returns the array. Single-record endpoints return the
    # body as-is.
    def data
      return body unless body.is_a?(Hash)

      body.key?("data") ? body["data"] : body
    end

    # The Manza-Version header echoed by the server, or the legacy
    # Zazu-Version one. Useful for debugging migration mismatches.
    def api_version
      headers["manza-version"] || headers["zazu-version"]
    end

    def to_h
      {
        status:,
        request_id:,
        api_version:,
        body:
      }.compact
    end

    def inspect
      "#<#{self.class.name} status=#{status} request_id=#{request_id.inspect}>"
    end
  end
end
