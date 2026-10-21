# frozen_string_literal: true

require "json"
require "openssl"

module Manza
  # Verifies incoming webhook deliveries. Pure functions — no HTTP.
  #
  # Every delivery carries `X-Manza-Signature` (hex HMAC-SHA256 of
  # "<timestamp>.<raw body>" under the endpoint's signing secret) and
  # `X-Manza-Timestamp` (Unix seconds, fresh on every attempt). The
  # legacy `X-Zazu-*` names carry the same values.
  #
  # Pass the **raw request body**, never re-serialized JSON:
  #
  #   event = Manza::Webhook.construct_event(
  #     payload: request.body.read, headers: request.env, secret: signing_secret
  #   )
  #   event["event"] # => "payment.authorization_requested"
  module Webhook
    DEFAULT_TOLERANCE = 300 # seconds

    module_function

    # Hex HMAC-SHA256 of "<timestamp>.<payload>". For tests and local tools.
    def sign(payload:, timestamp:, secret:)
      OpenSSL::HMAC.hexdigest("SHA256", secret, "#{timestamp}.#{payload}")
    end

    # true when the signature matches (constant time) and the timestamp is
    # within `tolerance` seconds of `now`. `tolerance: nil` skips the
    # timestamp check (for replaying a captured delivery). Never raises on
    # bad input; returns false.
    def verify?(payload:, signature:, timestamp:, secret:, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      signature_matches?(payload, signature, timestamp, secret) && timestamp_fresh?(timestamp, tolerance, now)
    end

    # Reads X-Manza-Signature / X-Manza-Timestamp from any Hash-like
    # headers (case-insensitive, X-Zazu-* fallback, Rack HTTP_X_MANZA_*
    # form too), verifies them, and returns the parsed JSON Hash. Raises
    # Manza::ArgumentError when a header is missing, the signature does
    # not match, the timestamp is outside tolerance, or the body is not
    # JSON.
    def construct_event(payload:, headers:, secret:, tolerance: DEFAULT_TOLERANCE, now: Time.now)
      normalized = normalize_headers(headers)
      signature = header(normalized, "signature")
      timestamp = header(normalized, "timestamp")

      raise Manza::ArgumentError, "invalid webhook signature" unless signature_matches?(payload, signature, timestamp, secret)
      raise Manza::ArgumentError, "webhook timestamp outside tolerance" unless timestamp_fresh?(timestamp, tolerance, now)

      begin
        JSON.parse(payload)
      rescue JSON::ParserError
        raise Manza::ArgumentError, "webhook payload is not JSON"
      end
    end

    def signature_matches?(payload, signature, timestamp, secret)
      return false unless [payload, signature, timestamp, secret].all? { |v| v.is_a?(String) || v.is_a?(Integer) }
      return false unless parse_timestamp(timestamp)

      expected = sign(payload: payload, timestamp: timestamp, secret: secret.to_s)
      return false unless expected.bytesize == signature.to_s.bytesize

      OpenSSL.fixed_length_secure_compare(expected, signature.to_s)
    end

    def timestamp_fresh?(timestamp, tolerance, now)
      return true if tolerance.nil?

      seconds = parse_timestamp(timestamp)
      !seconds.nil? && (now.to_i - seconds).abs <= tolerance
    end

    def parse_timestamp(timestamp)
      Integer(timestamp.to_s, 10)
    rescue ::ArgumentError, TypeError
      nil
    end

    def normalize_headers(headers)
      headers.to_h.transform_keys { |name| name.to_s.sub(/\AHTTP_/i, "").tr("_", "-").downcase }
    end

    def header(normalized, suffix)
      value = normalized["x-manza-#{suffix}"] || normalized["x-zazu-#{suffix}"]
      return value.to_s unless value.nil? || value.to_s.empty?

      raise Manza::ArgumentError, "missing X-Manza-#{suffix.capitalize} header"
    end

    private_class_method :signature_matches?, :timestamp_fresh?, :parse_timestamp, :normalize_headers, :header
  end
end
