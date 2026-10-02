# frozen_string_literal: true

require "faraday"
require "faraday/retry"
require "httpx/adapters/faraday"
require "json"
require "securerandom"

module Manza
  # The main SDK entry point.
  #
  #   manza = Manza::Client.new(api_key: "sk_live_...")
  #   manza.entity.get
  #   manza.accounts.list(limit: 50)
  #
  # All public state is set at construction time. The client is
  # thread-safe in the sense that the underlying Faraday connection
  # uses a connection pool via the HTTPX adapter — multiple threads
  # can share one client.
  class Client
    # Morocco production. South Africa: https://za.manza.finance.
    DEFAULT_BASE_URL = "https://ma.manza.finance"
    DEFAULT_TIMEOUT = 30
    USER_AGENT = "manza-ruby/#{VERSION}".freeze

    attr_reader :api_key, :base_url, :api_version, :timeout, :logger

    # Reads MANZA_<name>, falling back to the pre-1.0 ZAZU_<name> with a
    # one-time deprecation warning per variable. The fallback stays for
    # all of 1.x.
    #
    # @api private
    def self.env(name)
      value = ENV.fetch("MANZA_#{name}", nil)
      return value unless value.nil?

      legacy = ENV.fetch("ZAZU_#{name}", nil)
      return if legacy.nil?

      @warned_legacy_env ||= Set.new
      warn("[manza] ZAZU_#{name} is deprecated; set MANZA_#{name} instead.") if @warned_legacy_env.add?(name)
      legacy
    end

    def initialize(
      api_key: Client.env("API_KEY"),
      base_url: Client.env("BASE_URL") || DEFAULT_BASE_URL,
      api_version: Client.env("API_VERSION"),
      timeout: Integer(Client.env("TIMEOUT") || DEFAULT_TIMEOUT),
      logger: nil
    )
      raise ConfigurationError, "Missing api_key. Pass api_key: or set MANZA_API_KEY." if api_key.to_s.empty?

      @api_key = api_key
      @base_url = base_url.to_s.chomp("/")
      @api_version = api_version
      @timeout = timeout
      @logger = logger
    end

    # Resource accessors — each returns a memoized resource module.
    def accounts
      @accounts ||= Resources::Accounts.new(self)
    end

    def beneficiaries
      @beneficiaries ||= Resources::Beneficiaries.new(self)
    end

    def checkout_sessions
      @checkout_sessions ||= Resources::CheckoutSessions.new(self)
    end

    def customers
      @customers ||= Resources::Customers.new(self)
    end

    def entity
      @entity ||= Resources::Entity.new(self)
    end

    def invoices
      @invoices ||= Resources::Invoices.new(self)
    end

    def payment_links
      @payment_links ||= Resources::PaymentLinks.new(self)
    end

    def payee_trust_requests
      @payee_trust_requests ||= Resources::PayeeTrustRequests.new(self)
    end

    def transfer_drafts
      @transfer_drafts ||= Resources::TransferDrafts.new(self)
    end

    def webhook_endpoints
      @webhook_endpoints ||= Resources::WebhookEndpoints.new(self)
    end

    # Performs an HTTP request and returns a {Manza::Response} on
    # success. Translates non-2xx responses into the matching
    # {Manza::Error} subclass.
    def request(method, path, params: nil, body: nil, headers: {})
      raw = connection.send(method) do |req|
        req.url(path)
        req.params.update(params) if params
        req.body = body unless body.nil?
        headers.each { |k, v| req.headers[k] = v }
      end

      response = Response.new(raw)
      return response if response.success?

      raise build_error(response)
    rescue Faraday::TimeoutError => e
      raise ConnectionError, "Request timed out after #{timeout}s: #{e.message}"
    rescue Faraday::ConnectionFailed => e
      raise ConnectionError, "Connection failed: #{e.message}"
    end

    private

    def connection
      @connection ||= Faraday.new(url: base_url) do |f|
        f.headers["Authorization"] = "Bearer #{api_key}"
        f.headers["User-Agent"] = USER_AGENT
        f.headers["Accept"] = "application/json"
        f.headers["Manza-Version"] = api_version if api_version
        f.request :json
        f.response :json, content_type: /\bjson$/
        f.options.timeout = timeout
        f.options.open_timeout = [timeout, 10].min
        f.response :logger, logger if logger
        f.adapter(*adapter_args)
      end
    end

    # The HTTPX adapter ships its own WebMock plugin that wraps every
    # connection. When VCR's WebMock library hook is also active and
    # net-connect is allowed (recording mode), the two interceptors
    # layer in a way that deadlocks on the first real request. For
    # cassette recording we drop down to Net::HTTP, which has rock-
    # solid WebMock + VCR integration. Cassettes are adapter-agnostic
    # so replay continues to use the production HTTPX adapter.
    def adapter_args
      ENV["VCR_RECORD"] ? [:net_http] : [:httpx]
    end

    # Lookup table for status → (error class, default message). 5xx
    # is matched separately because Range keys don't work in Hash
    # lookup the way exact integers do.
    ERROR_BY_STATUS = {
      400 => [ValidationError, "Bad request"],
      401 => [AuthenticationError, "Authentication failed"],
      403 => [ForbiddenError, "Forbidden"],
      404 => [NotFoundError, "Not found"],
      422 => [ValidationError, "Validation failed"]
    }.freeze
    private_constant :ERROR_BY_STATUS

    def build_error(response)
      payload = error_payload(response.body)
      message = payload["message"]
      kwargs = error_kwargs(response, payload)

      if (mapping = ERROR_BY_STATUS[response.status])
        klass, default_message = mapping
        return klass.new(message || default_message, **kwargs)
      end

      build_special_error(response, payload, message, kwargs)
    end

    def error_payload(body)
      return {} unless body.is_a?(Hash) && body["error"].is_a?(Hash)

      body["error"]
    end

    def error_kwargs(response, payload)
      {
        status: response.status,
        request_id: response.request_id,
        type: payload["type"],
        param: payload["param"],
        body: response.body
      }
    end

    def build_special_error(response, payload, message, kwargs)
      case response.status
      when 409
        ConflictError.new(message || "Conflict", payment_id: payload["payment_id"], **kwargs)
      when 429
        retry_after = response.headers["retry-after"]&.to_i
        RateLimitError.new(message || "Rate limited", retry_after: retry_after, **kwargs)
      when 500..599
        ServerError.new(message || "Server error (#{response.status})", **kwargs)
      else
        Error.new(message || "Unexpected status #{response.status}", **kwargs)
      end
    end
  end
end
