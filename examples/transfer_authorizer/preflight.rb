# frozen_string_literal: true

# Checks every setup step before you create a transfer, and says how to fix
# the ones that fail:
#
#   bundle exec ruby preflight.rb          # for a 10.00 transfer
#   bundle exec ruby preflight.rb 250.00
#
# ✓ passed, ✗ failed (exit status 1), ! cannot be checked through the API.
require "time"
require "manza"

module TransferAuthorizer
  class Preflight
    SECRET_MIN_DAYS = 7
    # Hosts that hand out a new URL on every restart. An enrolled endpoint's
    # URL is locked, so the next restart breaks the authorizer.
    UNSTABLE_TUNNEL_HOSTS = %w[ngrok-free.app trycloudflare.com].freeze
    SUSPENSION_FIXES = {
      "member" => "an approver suspended it: resume it in Settings → Developer → Transfer approval",
      "signature_failures" => "five invalid signatures in a row: fix the signing, then an approver resumes it in the app",
      "secret_expired" => "an approver rotates the secret in the app (and resumes it if it stays suspended); " \
                          "set the new one as MANZA_AUTHORIZER_SECRET",
      "endpoint_disabled" => "re-enable the webhook endpoint (webhook_endpoints.enable), or enrol a new one if it was " \
                             "deleted; if it stays suspended, an approver resumes it in the app"
    }.freeze

    def initialize(env: ENV, amount: "10.00", out: $stdout, now: Time.now)
      @env = env
      @raw_amount = amount
      # Rational parses the API's decimal strings exactly, without the
      # bigdecimal gem (not a default gem since Ruby 3.4).
      # Plain decimals only: create_transfer.rb sends the string as is, so
      # "1/2" or "1e2" would parse here but not mean the same to the API.
      @amount = /\A\d+(?:\.\d+)?\z/.match?(amount.to_s) ? Rational(amount.to_s) : nil
      @amount = nil unless @amount&.positive?
      @out = out
      @now = now
      @ok = true
    end

    # Prints one line per step; true when no step failed.
    def run
      fail_step("amount #{@raw_amount.inspect} is not a positive decimal", "pass an amount like 10.00 or 250.00") unless @amount
      return @ok unless keys?

      creator_reaches_entity
      authorizer = enrolled_authorizer
      if authorizer
        currency_matches(authorizer)
        # An expired secret already failed the authorizer line, with its fix.
        secret_fresh(authorizer) unless authorizer["suspension_reason"] == "secret_expired"
      end
      secret_set
      if authorizer
        endpoint_enabled(authorizer)
        amount_within_limits(authorizer) if @amount
      end
      payee_trusted
      @ok
    end

    private

    # 1. Both keys (and the ids the other steps read) are set, the keys different.
    def keys?
      missing = %w[MANZA_CREATOR_API_KEY MANZA_AUTHORIZER_API_KEY MANZA_ACCOUNT_ID MANZA_BENEFICIARY_ID]
                .select { |name| value(name).empty? }
      if !missing.empty?
        fail_step("#{missing.join(", ")} not set", "set them in .env")
      elsif value("MANZA_CREATOR_API_KEY") == value("MANZA_AUTHORIZER_API_KEY")
        fail_step("key A and key B are the same key",
                  "use two different keys: the API refuses to let the key that created a transfer authorize it")
      else
        pass("key A and key B are set and different")
        return true
      end
      false
    end

    # 2. Key A reaches the API.
    def creator_reaches_entity
      entity = creator.entity.get.body
      pass("key A reaches the API (entity #{entity["name"].inspect})")
    rescue Manza::Error => e
      fail_step("key A cannot read the entity: #{describe(e)}", key_fix(e, "MANZA_CREATOR_API_KEY", "entity:read"))
    end

    # 3. Key B reads the authorizer, which must be active.
    def enrolled_authorizer
      authorizer = authorizer_client.transfer_authorizer.get.body
      if authorizer["status"] == "active"
        pass("transfer authorizer is active")
      else
        reason = authorizer["suspension_reason"]
        fail_step("transfer authorizer is #{authorizer["status"]} (#{reason})",
                  SUSPENSION_FIXES.fetch(reason, "see suspension_reason in the transfer authorization docs"))
      end
      authorizer
    rescue Manza::NotFoundError
      fail_step("no transfer authorizer is enrolled", "enrol your webhook endpoint in Settings → Developer → Transfer approval")
      nil
    rescue Manza::Error => e
      fail_step("key B cannot read the transfer authorizer: #{describe(e)}",
                key_fix(e, "MANZA_AUTHORIZER_API_KEY", "transfers:authorize"))
      nil
    end

    def currency_matches(authorizer)
      currency = creator.accounts.get(value("MANZA_ACCOUNT_ID")).body["currency_code"]
      return pass("account currency #{currency} is the enrolled currency") if currency == authorizer["currency_code"]

      fail_step("account currency #{currency} is not the enrolled currency #{authorizer["currency_code"]}",
                "pay from a #{authorizer["currency_code"]} account (MANZA_ACCOUNT_ID), or enrol #{currency}")
    rescue Manza::Error => e
      fail_step("key A cannot read account #{value("MANZA_ACCOUNT_ID").inspect}: #{describe(e)}",
                key_fix(e, "MANZA_CREATOR_API_KEY", "accounts:read", "MANZA_ACCOUNT_ID"))
    end

    def secret_fresh(authorizer)
      expires_at = Time.iso8601(authorizer["secret_expires_at"])
      days = ((expires_at - @now) / 86_400).floor
      return pass("signing secret expires in #{days} days") if days >= SECRET_MIN_DAYS

      fail_step("signing secret #{days.negative? ? "expired" : "expires in #{days} days"} (#{authorizer["secret_expires_at"]})",
                "an approver should rotate the secret in Settings → Developer → Transfer approval; set the new one as " \
                "MANZA_AUTHORIZER_SECRET")
    end

    # 4. The signing secret is set.
    def secret_set
      return pass("MANZA_AUTHORIZER_SECRET is set") unless value("MANZA_AUTHORIZER_SECRET").empty?

      fail_step("MANZA_AUTHORIZER_SECRET is not set", "set it to the signing secret shown at enrolment or at the last rotation")
    end

    # 5. The enrolled webhook endpoint is enabled, on a URL that lasts.
    def endpoint_enabled(authorizer)
      endpoint = creator.webhook_endpoints.get(authorizer["webhook_endpoint_id"]).body
      if endpoint["status"] == "active"
        pass("webhook endpoint #{endpoint["url"]} is enabled")
      else
        fail_step("webhook endpoint #{endpoint["url"]} is #{endpoint["status"]}",
                  "enable it (webhook_endpoints.enable(#{endpoint["id"].inspect})); if the authorizer stays suspended, " \
                  "an approver resumes it in the app")
      end
      host = URI(endpoint["url"].to_s).host.to_s
      unstable = UNSTABLE_TUNNEL_HOSTS.find { |domain| host.end_with?(domain) }
      return unless unstable

      warn_step("webhook endpoint is on #{unstable}, whose URL changes when the tunnel restarts",
                "use a reserved domain or a named tunnel, then enrol an endpoint at that URL")
    rescue Manza::NotFoundError
      fail_step("the enrolled webhook endpoint #{authorizer["webhook_endpoint_id"]} was deleted",
                "create an endpoint at a stable URL and enrol it in Settings → Developer → Transfer approval")
    rescue Manza::Error => e
      fail_step("key A cannot read the enrolled webhook endpoint: #{describe(e)}",
                key_fix(e, "MANZA_CREATOR_API_KEY", "webhook_endpoints:read"))
    end

    # 6a. The test amount fits both limits.
    def amount_within_limits(authorizer)
      per_transfer = Rational(authorizer["per_transfer_limit"])
      room = Rational(authorizer["daily_limit"]) - Rational(authorizer["daily_authorized_total"])
      if @amount > per_transfer
        fail_step("#{format_amount(@amount)} is over the limit per transfer (#{format_amount(per_transfer)})",
                  "send at most #{format_amount(per_transfer)}, or have an approver raise the limit")
      elsif @amount > room
        fail_step("#{format_amount(@amount)} does not fit the last 24 hours' room (#{format_amount(room)} left)",
                  "wait for older authorizations to leave the 24-hour window, or have an approver raise the limit")
      else
        pass("#{format_amount(@amount)} is within the limit per transfer and the 24-hour room")
      end
    end

    # 6b. The payee is trusted, or may be trusted on authorize.
    def payee_trusted
      beneficiary = creator.beneficiaries.get(value("MANZA_BENEFICIARY_ID")).body
      account = Array(beneficiary["external_accounts"]).find { |a| a["default"] }
      return fail_step("beneficiary has no default bank account", "add one, or set a beneficiary that has one") unless account
      return pass("payee #{account["id"]} is trusted") if account["trusted"]

      warn_step("payee #{account["id"]} is not trusted yet",
                "it qualifies only with \"Approve transfers to new payees\" on in Settings → Developer → Transfer approval " \
                "(not visible through the API), key A bound to an IP allowlist, and the amount within the limit per " \
                "transfer to a new payee; otherwise have an approver trust it")
    rescue Manza::Error => e
      fail_step("key A cannot read beneficiary #{value("MANZA_BENEFICIARY_ID").inspect}: #{describe(e)}",
                key_fix(e, "MANZA_CREATOR_API_KEY", "beneficiaries:read", "MANZA_BENEFICIARY_ID"))
    end

    def creator
      @creator ||= Manza.new(api_key: value("MANZA_CREATOR_API_KEY"), base_url: base_url)
    end

    def authorizer_client
      @authorizer_client ||= Manza.new(api_key: value("MANZA_AUTHORIZER_API_KEY"), base_url: base_url)
    end

    def base_url
      value("MANZA_BASE_URL").empty? ? Manza::Client::DEFAULT_BASE_URL : value("MANZA_BASE_URL")
    end

    def value(name)
      @env.fetch(name, "").to_s
    end

    def describe(error)
      "#{error.class.name} #{error.type || error.status}: #{error.message}"
    end

    def key_fix(error, key_var, scope, id_var = nil)
      case error
      when Manza::AuthenticationError then "check #{key_var}: the key is wrong or revoked"
      when Manza::ForbiddenError then "give the key the #{scope} scope, or add this machine's address to its IP allowlist"
      when Manza::NotFoundError then "check #{id_var || "MANZA_BASE_URL"}"
      else "check MANZA_BASE_URL and the network, then rerun"
      end
    end

    def format_amount(amount)
      format("%.2f", amount)
    end

    def pass(message)
      @out.puts("✓ #{message}")
    end

    def fail_step(message, fix)
      @ok = false
      @out.puts("✗ #{message}: #{fix}")
    end

    def warn_step(message, note)
      @out.puts("! #{message}: #{note}")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "dotenv"
  Dotenv.overload(File.expand_path(".env", __dir__))
  exit(TransferAuthorizer::Preflight.new(amount: ARGV.fetch(0, "10.00")).run ? 0 : 1)
end
