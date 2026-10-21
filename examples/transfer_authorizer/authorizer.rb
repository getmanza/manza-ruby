# frozen_string_literal: true

require "logger"
require "manza"
require_relative "ledger"

module TransferAuthorizer
  # A Rack app that answers `payment.authorization_requested` webhooks
  # with key B (the authorizer key):
  #
  #   1. Verify the delivery (401 when the signature or timestamp is bad).
  #   2. Find the draft in your own ledger by its client_reference.
  #   3. Missing or different from what you created → decline with a reason.
  #   4. Otherwise sign the challenge from the ledger and authorize it.
  #
  # It answers 200 first and does steps 2-4 on the executor (a background
  # thread by default): the delivery has a timeout, and a retried webhook
  # is safe because authorize replays idempotently.
  class App
    EVENT = "payment.authorization_requested"

    # Ledger field → webhook `data.payment` field. All must match.
    CHECKED_FIELDS = {
      "payment_id" => "id",
      "amount" => "amount",
      "currency_code" => "currency_code",
      "account_id" => "account_id",
      "payee" => "payee"
    }.freeze

    # Failures worth another try: the API did not answer, or asked us to slow
    # down. Authorize and decline replay idempotently, so a retry is safe.
    TRANSIENT_ERRORS = [Manza::ServerError, Manza::ConnectionError, Manza::RateLimitError].freeze
    ATTEMPTS = 3
    MAX_RETRY_AFTER = 30 # seconds; a challenge expires, so never park the thread for long

    # `ledger_wait`: seconds to wait for the ledger entry. The webhook can
    # arrive before create_transfer.rb has written the entry from the
    # create response. `retry_delay`: base seconds between attempts.
    def initialize(client:, secret:, ledger:, executor: ->(&job) { Thread.new(&job) },
                   logger: Logger.new($stdout), ledger_wait: 10, retry_delay: 2)
      @client = client
      @secret = secret
      @ledger = ledger
      @executor = executor
      @logger = logger
      @ledger_wait = ledger_wait
      @retry_delay = retry_delay
    end

    def call(env)
      body = env["rack.input"].read
      event = verify(body, env)
      return respond(401) unless event

      return ignore(event) unless event["event"] == EVENT

      @executor.call { answer(event["data"]) }
      respond(200)
    end

    private

    def verify(body, env)
      event = Manza::Webhook.construct_event(payload: body, headers: env, secret: @secret)
      @logger.info("received #{event["event"]} (#{event["event_id"]}), signature verified")
      event
    rescue Manza::ArgumentError => e
      @logger.warn("rejected a delivery: #{e.message}")
      nil
    end

    def ignore(event)
      @logger.info("ignoring #{event["event"]}: this app only answers #{EVENT}")
      respond(200)
    end

    def answer(data)
      payment = data.fetch("payment")
      authorization = data.fetch("authorization")
      client_reference = payment["client_reference"]
      entry = wait_for_entry(client_reference)

      mismatch = entry ? mismatch_reason(entry, payment) : "client_reference #{client_reference.inspect} is not in the ledger"
      return decline(payment["id"], authorization["id"], mismatch) if mismatch

      @logger.info("ledger match for #{client_reference}: #{payment["amount"]} #{payment["currency_code"]} to #{payment["payee"]}")
      authorize(entry, authorization, client_reference, data["signature_input"])
    rescue Manza::Error => e
      @logger.error("API error #{e.class.name}: #{e.message} (type #{e.type.inspect}, request_id #{e.request_id.inspect})")
    rescue StandardError => e
      @logger.error("could not answer the challenge: #{e.class}: #{e.message}")
    end

    def wait_for_entry(client_reference)
      deadline = Time.now + @ledger_wait
      loop do
        entry = @ledger.find(client_reference)
        return entry if entry || Time.now >= deadline

        sleep 0.5
      end
    end

    def mismatch_reason(entry, payment)
      field, = CHECKED_FIELDS.find { |ledger_field, webhook_field| entry[ledger_field] != payment[webhook_field] }
      return unless field

      "#{field} differs from the ledger (ledger #{entry[field].inspect}, webhook #{payment[CHECKED_FIELDS[field]].inspect})"
    end

    # Sign from the ledger, never from the webhook: `signature_input` in the
    # webhook is only there to compare against.
    def authorize(entry, authorization, client_reference, webhook_input)
      input = Manza::TransferAuthorization.signature_input(
        payment_id: entry["payment_id"], nonce: authorization["nonce"], amount: entry["amount"],
        currency_code: entry["currency_code"], account_id: entry["account_id"], payee: entry["payee"],
        client_reference: client_reference
      )
      # A signature over a different input is sure to fail, and failed
      # attempts count toward suspending the authorizer. Leave the challenge
      # unanswered instead: it expires and goes to your approvers.
      unless input == webhook_input
        @logger.warn("signature input differs from the webhook's: ledger #{input.inspect}, webhook #{webhook_input.inspect}; " \
                     "not answering, the challenge goes to your approvers when it expires")
        return
      end

      signature = Manza::TransferAuthorization.sign(secret: @secret, signature_input: input)
      @logger.info("signed the challenge for payment #{entry["payment_id"]}")

      response = with_retries do
        @client.transfer_drafts.authorize(entry["payment_id"], authorization_id: authorization["id"], signature: signature)
      end
      @logger.info("authorized payment #{entry["payment_id"]} (status #{response.body["status"].inspect})")
    end

    def decline(payment_id, authorization_id, reason)
      with_retries { @client.transfer_drafts.decline(payment_id, authorization_id: authorization_id, reason: reason) }
      @logger.warn("declined payment #{payment_id}: #{reason}")
    end

    def with_retries
      attempt = 1
      begin
        yield
      rescue *TRANSIENT_ERRORS => e
        raise if attempt >= ATTEMPTS

        delay = e.is_a?(Manza::RateLimitError) && e.retry_after ? [e.retry_after, MAX_RETRY_AFTER].min : @retry_delay * attempt
        @logger.warn("#{e.class.name} (request_id #{e.request_id.inspect}), retrying in #{delay}s")
        sleep delay
        attempt += 1
        retry
      end
    end

    def respond(status)
      [status, { "content-type" => "text/plain" }, [status == 200 ? "ok" : "unauthorized"]]
    end
  end
end
