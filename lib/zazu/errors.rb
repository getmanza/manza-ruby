# frozen_string_literal: true

module Zazu
  # Base class for every Zazu SDK error.
  #
  # Carries the HTTP status, the API request id (header `X-Request-Id`),
  # the parsed error type from the API (`error.type`), and the raw
  # response body so callers can introspect anything the SDK didn't
  # explicitly model.
  class Error < StandardError
    attr_reader :status, :request_id, :type, :param, :body

    def initialize(message = nil, status: nil, request_id: nil, type: nil, param: nil, body: nil)
      super(message)
      @status = status
      @request_id = request_id
      @type = type
      @param = param
      @body = body
    end

    def to_h
      {
        error: self.class.name.split("::").last,
        message:,
        status:,
        request_id:,
        type:,
        param:
      }.compact
    end
  end

  # 401 — bearer token missing, malformed, or revoked.
  class AuthenticationError < Error; end

  # 403 — token valid but lacks the required scope, OR the entity is
  # not yet active, OR the API feature flag is off for this entity.
  class ForbiddenError < Error; end

  # 404 — the requested resource does not exist (or this entity cannot
  # see it).
  class NotFoundError < Error; end

  # 400 / 422 — request body or query params failed validation (400 for
  # a malformed request such as a bad `limit`/`cursor`, 422 for a
  # well-formed one the API rejects). `#param` carries the offending
  # field name when the API supplies it.
  class ValidationError < Error; end

  # 409 — the request conflicts with an existing resource. For a
  # duplicate `client_reference` on a transfer draft (`type`
  # "duplicate_client_reference"), `#payment_id` names the draft that
  # already holds it.
  class ConflictError < Error
    attr_reader :payment_id

    def initialize(message = nil, payment_id: nil, **)
      super(message, **)
      @payment_id = payment_id
    end

    def to_h
      super.merge(payment_id:).compact
    end
  end

  # 429 — rate limited. Retry after the `Retry-After` header (seconds).
  class RateLimitError < Error
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **)
      super(message, **)
      @retry_after = retry_after
    end
  end

  # 5xx — server error. Worth retrying once with backoff.
  class ServerError < Error; end

  # Network timeout, connection refused, DNS failure — anything that
  # prevents the SDK from hearing back from the API.
  class ConnectionError < Error; end

  # The SDK was misconfigured (no API key, invalid base URL, etc.).
  # Raised before any HTTP request is attempted.
  class ConfigurationError < Error; end

  # Caller passed a value the SDK refuses to send (e.g. `limit > 100`).
  # Distinct from `ValidationError`, which represents server-side
  # validation rejection.
  class ArgumentError < Error; end
end
