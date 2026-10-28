# frozen_string_literal: true

# Rake tasks that seed the staging entity with the records needed to
# record VCR cassettes for the spec suite. The tasks are designed to
# be run in this order on first-time setup:
#
#   bundle exec rake fixtures:teardown   # clean any prior fixtures
#   bundle exec rake fixtures:seed       # create fresh ones; prints .env IDs
#   # paste the printed IDs into .env
#   bundle exec rake fixtures:record     # re-record cassettes
#
# All seeded records carry the FIXTURE_TAG marker in a structural
# field (`company_name` for customers, `description` for webhook
# endpoints, etc.) so teardown can find and delete them on a future
# run. Re-running `seed` with stale fixtures present will exit with
# an error pointing at teardown.
#
# Requires .env with:
#   MANZA_STAGING_API_KEY  — must have read+write scopes for every
#                            resource we seed (customers, invoices,
#                            payment_links, webhook_endpoints).
#   MANZA_STAGING_URL       — usually https://ma.manza.dev.
#   MANZA_FIXTURE_ACCOUNT_ID — must be a real account in the entity
#                              the API key belongs to. The seed
#                              cannot create accounts (that's a
#                              banking-side operation), so this one
#                              ID has to come from outside.
#   MANZA_FIXTURE_BENEFICIARY_ID — the beneficiary whose default bank
#                              account is a trusted payee (setup
#                              step 5). Hand-provided, like
#                              the account: API-created beneficiaries
#                              pile up (no delete) and are never trusted.
#   MANZA_STAGING_AUTHORIZER_API_KEY — a second key with
#                              `transfers:authorize`. The API refuses to
#                              let a draft's creating key authorize it.
#   MANZA_STAGING_AUTHORIZER_SECRET — signing secret of the webhook
#                              endpoint enrolled as transfer authorizer.
#   MANZA_STAGING_AUTHORIZER_PORT — local port the authorizer endpoint's
#                              tunnel forwards to (default 4599).
#
# Staging setup. Steps 1-4 are kept in place by `sdk_fixtures_ensure`
# through the `manza` MCP gateway (AGENTS.md → Staging fixture state);
# `rake fixtures:preflight` (run by seed and record) aborts before
# anything is deleted when the authorizer is not active. Declared state:
# lib/tasks/staging_fixture_state.json.
#
#   1. `release_api_transfers` and `release_api_webhook_authorization`
#      on for the fixture entity.
#   2. MANZA_STAGING_API_KEY holds the scopes in the declared state,
#      `beneficiaries:write` and `beneficiaries:request_trust` among them,
#      and `transfers:authorize`: the authorize_same_key cassette records
#      this creating key refused by the same-key rule, which sits behind
#      the scope check (without the scope it records insufficient_scope).
#   3. MANZA_STAGING_AUTHORIZER_API_KEY holds `transfers:authorize`, and
#      both keys allowlist this machine's public addresses.
#   4. The transfer authorizer is active, with limits covering 10.00 MAD
#      (the API minimum) and its signing secret in
#      MANZA_STAGING_AUTHORIZER_SECRET (`sdk_fixtures_rotate_secret` when
#      it nears expiry).
#   5. A beneficiary's default bank account is a trusted payee
#      (`sdk_fixtures_trust_payee`), and the beneficiary's id is stored as
#      MANZA_FIXTURE_BENEFICIARY_ID. Make it an entity-owned account so
#      the money comes back, and keep a balance on MANZA_FIXTURE_ACCOUNT_ID.
#
# The one human step left: enrolling the authorizer in the app (OTP),
# with a webhook endpoint at a stable tunnel URL (cloudflared / ngrok
# reserved domain) forwarding to MANZA_STAGING_AUTHORIZER_PORT. Its
# creator must be an active member allowed to authorize and delete
# payments.
#
# MONEY MOVES: the authorize cassette executes a real 10.00 MAD transfer
# to the trusted payee on every re-record.
#
# The machine-authorization challenge expires after 1h, so seed and
# record must run in the same `rake fixtures:record`. Seed and record
# also share one process: the webhook receiver starts before the first
# draft is seeded and keeps answering deliveries until the process
# exits, so the authorizer endpoint does not collect failed deliveries.

require "dotenv"
require "ipaddr"
require "json"
require "net/http"
# Use overload so the file's values beat any stale exports in the
# developer's shell — `rake fixtures:seed` rewrites IDs into .env on
# every run, and a stale exported $MANZA_FIXTURE_CUSTOMER_ID would
# otherwise mask the freshly seeded one.
Dotenv.overload

# All seeding logic lives in the namespace below. Kept inline rather
# than pulled into lib/manza/* because this is purely a development
# tool — it has no place in the gem itself.
module Fixtures
  class Seeder
    # Marker baked into every seeded record so teardown can find them.
    FIXTURE_TAG = "zazu-ruby-fixture"
    FIXTURE_VERSION = "1" # bump when seed shape changes meaningfully

    REQUIRED_ENV = %w[MANZA_STAGING_API_KEY MANZA_STAGING_URL MANZA_FIXTURE_ACCOUNT_ID].freeze
    # Only seeding needs these; teardown must work without them.
    SEED_ENV = %w[
      MANZA_FIXTURE_BENEFICIARY_ID MANZA_STAGING_AUTHORIZER_API_KEY MANZA_STAGING_AUTHORIZER_SECRET
    ].freeze

    # Seconds to wait for the three payment.authorization_requested webhooks.
    AUTHORIZATION_WEBHOOK_TIMEOUT = 120

    # Keys we will print to stdout, in .env-paste-ready order.
    #
    # Note: invoice state-transition fixtures (sendable, payable,
    # cancellable, creditable) are not seeded here because the
    # public API does not expose the `pending_approval → approved`
    # transition. Without that, send/mark_as_paid/cancel/credit_note
    # cannot be exercised in v0.1.0. Cassettes for those land in a
    # later release once the API surfaces an approve endpoint or we
    # build a Rails-side helper that approves fixture invoices.
    EMITTED_KEYS = %w[
      MANZA_FIXTURE_TRANSACTION_ID
      MANZA_FIXTURE_CUSTOMER_ID
      MANZA_FIXTURE_DELETABLE_CUSTOMER_ID
      MANZA_FIXTURE_INVOICE_ID
      MANZA_FIXTURE_DELETABLE_INVOICE_ID
      MANZA_FIXTURE_PAYMENT_LINK_ID
      MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID
      MANZA_FIXTURE_WEBHOOK_ID
      MANZA_FIXTURE_ENABLED_WEBHOOK_ID
      MANZA_FIXTURE_DISABLED_WEBHOOK_ID
      MANZA_FIXTURE_DELETABLE_WEBHOOK_ID
      MANZA_FIXTURE_CHECKOUT_SESSION_ID
      MANZA_FIXTURE_TRANSFER_DRAFT_ID
      MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID
      MANZA_FIXTURE_CREATED_BENEFICIARY_ID
      MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID
      MANZA_FIXTURE_NEW_ACCOUNT_NUMBER
      MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID
      MANZA_FIXTURE_CLIENT_REFERENCE
      MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE
      MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID
      MANZA_FIXTURE_DECLINABLE_DRAFT_ID
      MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID
      MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID
      MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID
      MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID
      MANZA_FIXTURE_AUTHORIZABLE_NONCE
    ].freeze

    def initialize
      check_env!
      $LOAD_PATH.unshift(File.expand_path("../..", __dir__))
      require "manza"
      @client = Manza::Client.new(
        api_key: ENV.fetch("MANZA_STAGING_API_KEY"),
        base_url: ENV.fetch("MANZA_STAGING_URL")
      )
      @account_id = ENV.fetch("MANZA_FIXTURE_ACCOUNT_ID")
      @ids = {}
    end

    def run!
      check_env!(SEED_ENV)
      log "Checking for stale fixtures…"
      stale = find_stale_fixtures
      total_stale = stale.values.sum(&:size)
      if total_stale.positive?
        warn "!! Existing fixture records found on staging. Run `rake fixtures:teardown` first:"
        stale.each { |kind, items| warn "    #{kind}: #{items.size} record(s)" if items.any? }
        exit 1
      end

      log "Discovering transaction id…"
      discover_transaction_id!

      log "Seeding customers…"
      seed_customers!

      log "Seeding invoices…"
      seed_invoices!

      log "Seeding payment links…"
      seed_payment_links!

      log "Seeding webhook endpoints…"
      seed_webhook_endpoints!

      log "Seeding checkout session…"
      seed_checkout_session!

      log "Looking up the trusted payee…"
      discover_trusted_external_account_id!

      # Before any draft: every draft to the trusted payee fires a
      # payment.authorization_requested webhook.
      log "Starting the authorization webhook receiver…"
      start_authorization_receiver!

      log "Seeding transfer draft…"
      seed_transfer_draft!

      log "Seeding beneficiary, bank account and payee trust request…"
      seed_beneficiary!

      log "Seeding machine-authorization drafts (waiting for webhooks)…"
      seed_machine_authorizations!

      emit_env_block
    end

    def teardown!
      log "Looking up existing fixtures to delete…"
      stale = find_stale_fixtures
      total = stale.values.sum(&:size)

      if total.zero?
        log "No fixtures to delete. Nothing to do."
        return
      end

      log "Deleting #{total} fixture record(s)…"

      # Delete in dependency order: webhook endpoints, payment links,
      # invoices (which deletes invoice items), then customers.
      delete_each(stale[:webhook_endpoints]) { |id| @client.webhook_endpoints.delete(id) }
      delete_each(stale[:payment_links])     { |id| try_cancel_payment_link(id) }
      delete_each(stale[:invoices])          { |id| try_delete_invoice(id) }
      delete_each(stale[:customers])         { |id| try_delete_customer(id) }

      log "Teardown complete."
    end

    private

    def check_env!(required = REQUIRED_ENV)
      missing = required.select { |k| ENV.fetch(k, "").empty? }
      return if missing.empty?

      warn "Missing required env vars: #{missing.join(", ")}"
      warn "Copy .env.example to .env and fill in the values."
      exit 1
    end

    def log(msg)
      warn "[fixtures] #{msg}"
    end

    def fixture_marker(suffix = nil)
      [FIXTURE_TAG, "v#{FIXTURE_VERSION}", suffix].compact.join("-")
    end

    # --- Seed steps ---------------------------------------------------------

    # Transactions are read-only — they're created as a side effect of
    # bank movements, not via the API. We pluck the most recent one
    # off the fixture account so the get_transaction spec has a real
    # ID to replay against.
    def discover_transaction_id!
      page = @client.accounts.list_transactions(@account_id, limit: 1)
      first = page.data.first
      raise "No transactions found on fixture account — cannot record get_transaction cassette" unless first

      @ids["MANZA_FIXTURE_TRANSACTION_ID"] = first["id"]
    end

    def seed_customers!
      @ids["MANZA_FIXTURE_CUSTOMER_ID"] = create_customer!("primary").body["id"]
      @ids["MANZA_FIXTURE_DELETABLE_CUSTOMER_ID"] = create_customer!("deletable").body["id"]
    end

    def create_customer!(suffix)
      @client.customers.create(
        customer_type: "business",
        company_name: "Manza Fixture Co — #{suffix} (#{fixture_marker})",
        email: "fixture-#{suffix}-#{SecureRandom.hex(4)}@example.com",
        ice_number: random_ice_number
      )
    end

    def seed_invoices!
      customer_id = @ids.fetch("MANZA_FIXTURE_CUSTOMER_ID")

      # Two invoices in the API's default starting state
      # (`pending_approval`): one for read-only specs (list/get/
      # update), one earmarked for the delete spec.
      #
      # The send/mark_as_paid/cancel/credit_note specs need invoices
      # in the `approved` and `sent` states, which the public API
      # cannot transition into. Those specs are skipped in v0.1.0.
      drafts = Array.new(2) { |i| create_draft_invoice!(customer_id, i) }

      @ids["MANZA_FIXTURE_INVOICE_ID"] = drafts[0]
      @ids["MANZA_FIXTURE_DELETABLE_INVOICE_ID"] = drafts[1]
    end

    def create_draft_invoice!(customer_id, idx)
      response = @client.invoices.create(
        customer_id: customer_id,
        currency_code: "MAD",
        issue_date: Date.today.iso8601,
        due_date: (Date.today + 30).iso8601,
        reference: fixture_marker("inv-#{idx}"),
        notes: "[#{FIXTURE_TAG}] draft #{idx}",
        items: [
          { description: "Manza fixture line item", quantity: 1, unit_price: "100.00" }
        ]
      )
      response.body["id"]
    end

    def seed_payment_links!
      @ids["MANZA_FIXTURE_PAYMENT_LINK_ID"] = create_payment_link!("primary")
      @ids["MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID"] = create_payment_link!("cancellable")
    end

    def create_payment_link!(suffix)
      response = @client.payment_links.create(
        account_id: @account_id,
        amount: "100.00",
        title: "Manza Fixture — #{suffix}",
        description: "[#{FIXTURE_TAG}] #{suffix}",
        payment_reference: "fixture-#{suffix}-#{SecureRandom.hex(4)}",
        link_type: "single"
      )
      response.body["id"]
    end

    def seed_webhook_endpoints!
      @ids["MANZA_FIXTURE_WEBHOOK_ID"] = create_webhook_endpoint!("primary")
      @ids["MANZA_FIXTURE_ENABLED_WEBHOOK_ID"] = create_webhook_endpoint!("enabled")

      # disabled: create then disable.
      disabled_id = create_webhook_endpoint!("disabled")
      @client.webhook_endpoints.disable(disabled_id)
      @ids["MANZA_FIXTURE_DISABLED_WEBHOOK_ID"] = disabled_id

      @ids["MANZA_FIXTURE_DELETABLE_WEBHOOK_ID"] = create_webhook_endpoint!("deletable")
    end

    def create_webhook_endpoint!(suffix)
      response = @client.webhook_endpoints.create(
        url: "https://example.com/zazu-fixture-#{suffix}-#{SecureRandom.hex(4)}",
        events: ["payment_link.paid"],
        description: "[#{FIXTURE_TAG}] #{suffix}"
      )
      response.body["id"]
    end

    # Checkout sessions have no list/update/delete endpoints — they
    # just sit on staging once created. We don't include them in
    # find_stale_fixtures or teardown because there's no API to find
    # or clean them. A fresh one is created on every seed run; the
    # old ones are inert (their cassettes are scrubbed before commit).
    def seed_checkout_session!
      response = @client.checkout_sessions.create(
        account_id: @account_id,
        amount: "100.00",
        success_url: "https://example.com/zazu-fixture-success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "https://example.com/zazu-fixture-cancel",
        description: "[#{FIXTURE_TAG}] checkout session",
        customer_email: "fixture-checkout-#{SecureRandom.hex(4)}@example.com",
        metadata: { fixture_marker: fixture_marker("checkout") }
      )
      @ids["MANZA_FIXTURE_CHECKOUT_SESSION_ID"] = response.body["id"]
    end

    # The machine-authorization path needs a *trusted* payee, and only a
    # member can grant trust (in the app, behind OTP). So rather than
    # seeding one, we reuse the hand-provided beneficiary whose default
    # bank account was marked trusted once (setup step 5).
    def discover_trusted_external_account_id!
      beneficiary_id = ENV.fetch("MANZA_FIXTURE_BENEFICIARY_ID")
      beneficiary = @client.beneficiaries.get(beneficiary_id).body
      trusted = beneficiary["external_accounts"].find { |a| a["default"] }
      raise "Beneficiary #{beneficiary_id} has no default bank account — see setup step 5" unless trusted

      @ids["MANZA_FIXTURE_BENEFICIARY_ID"] = beneficiary_id
      @ids["MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID"] = trusted["id"]
    end

    def start_authorization_receiver!
      @receiver = AuthorizationReceiver.start(
        port: Integer(ENV.fetch("MANZA_STAGING_AUTHORIZER_PORT", "4599")),
        secret: ENV.fetch("MANZA_STAGING_AUTHORIZER_SECRET")
      )
    end

    # There is no delete endpoint for transfer drafts; like checkout
    # sessions, seeded drafts sit on staging and are excluded from
    # find_stale_fixtures/teardown. This one targets the trusted payee,
    # so it gets a machine-authorization challenge that nobody answers:
    # after 1h it falls back to the in-app approvers. Do not approve it.
    def seed_transfer_draft!
      response = @client.transfer_drafts.create(
        account_id: @account_id,
        beneficiary_id: @ids.fetch("MANZA_FIXTURE_BENEFICIARY_ID"),
        amount: "10.00",
        payment_reference: fixture_marker("transfer"),
        internal_notes: "[#{FIXTURE_TAG}] transfer draft — do not approve"
      )
      @ids["MANZA_FIXTURE_TRANSFER_DRAFT_ID"] = response.body["id"]
    end

    # There is no delete endpoint for beneficiaries, bank accounts or
    # trust requests. API-created ones stay on staging, inert, and are
    # excluded from teardown. The trust request stays `pending`: nobody
    # approves it, so the seeded account never becomes a trusted payee.
    def seed_beneficiary!
      beneficiary = @client.beneficiaries.create(
        beneficiary_type: "business",
        company_name: "Manza Fixture Beneficiary - created (#{fixture_marker})",
        email: "fixture-created-beneficiary-#{SecureRandom.hex(4)}@example.com"
      ).body
      account = @client.beneficiaries.create_external_account(
        beneficiary["id"], account_number: random_rib, name: "Fixture Seeded Account"
      ).body
      trust_request = @client.payee_trust_requests.create(external_account_ids: [account["id"]]).body

      @ids["MANZA_FIXTURE_CREATED_BENEFICIARY_ID"] = beneficiary["id"]
      @ids["MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"] = account["id"]
      @ids["MANZA_FIXTURE_PAYEE_TRUST_REQUEST_ID"] = trust_request["id"]
      # Account numbers are unique per entity: the create_external_account
      # spec needs a fresh one on every record.
      @ids["MANZA_FIXTURE_NEW_ACCOUNT_NUMBER"] = random_rib
      # Unused here: the transfer_drafts#create spec sends it.
      @ids["MANZA_FIXTURE_CLIENT_REFERENCE"] = random_client_reference("create")
    end

    # Three drafts to the trusted payee, each answered by a different
    # spec: authorize (200, executes 10.00 MAD), decline (200), and a bad
    # signature (422). The authorization id and nonce arrive only in the
    # payment.authorization_requested webhook, so the local receiver
    # captures them.
    #
    # Like the seed draft, the bad-signature draft is left with a failed
    # attempt and falls back to the in-app approvers after 1h; the
    # declined one is deleted. Do not approve leftovers.
    def seed_machine_authorizations!
      drafts = %w[authorizable declinable bad_signature].to_h do |kind|
        [kind, create_machine_draft!(kind)]
      end
      @ids["MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE"] = drafts["authorizable"]["client_reference"]

      challenges = @receiver.wait_for(drafts.values.map { |d| d["id"] }, timeout: AUTHORIZATION_WEBHOOK_TIMEOUT)

      drafts.each do |kind, draft|
        prefix = "MANZA_FIXTURE_#{kind.upcase}"
        @ids["#{prefix}_DRAFT_ID"] = draft["id"]
        @ids["#{prefix}_AUTHORIZATION_ID"] = challenges.fetch(draft["id"]).fetch("authorization_id")
      end
      @ids["MANZA_FIXTURE_AUTHORIZABLE_NONCE"] = challenges.fetch(drafts["authorizable"]["id"]).fetch("nonce")
    end

    def create_machine_draft!(kind)
      draft = @client.transfer_drafts.create(
        account_id: @account_id,
        beneficiary_id: @ids.fetch("MANZA_FIXTURE_BENEFICIARY_ID"),
        external_account_id: @ids.fetch("MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID"),
        amount: "10.00",
        payment_reference: fixture_marker(kind.tr("_", "-")),
        client_reference: random_client_reference(kind)
      ).body
      return draft if draft["authorization"]

      raise "Draft #{draft["id"]} (#{kind}) went to the in-app approvers instead of the authorizer. " \
            "Run sdk_fixtures_ensure (AGENTS.md → Staging fixture state), then check setup step 5 in lib/tasks/fixtures.rake."
    end

    # --- Teardown steps -----------------------------------------------------

    # Returns { customers: [ids], invoices: [ids], ... } of fixture-tagged records.
    def find_stale_fixtures
      {
        customers: stale_customers,
        invoices: stale_invoices,
        payment_links: stale_payment_links,
        webhook_endpoints: stale_webhook_endpoints
      }
    end

    def stale_customers
      stale_records(@client.customers) { |c| fixture_record?(c["company_name"]) }
    end

    def stale_invoices
      stale_records(@client.invoices) do |i|
        # Teardown cancels invoices it cannot delete; treat those as gone.
        next false if i["status"] == "cancelled"

        fixture_record?(i["reference"]) || fixture_record?(i.dig("customer", "name"))
      end
    end

    def stale_payment_links
      stale_records(@client.payment_links) do |pl|
        # Payment links can't be hard-deleted via the API. Once
        # cancelled, treat them as gone for the purpose of seed-time
        # staleness — the next seed will create fresh ones.
        next false if pl["status"] == "cancelled"

        fixture_record?(pl["title"]) || fixture_record?(pl["description"])
      end
    end

    def stale_webhook_endpoints
      stale_records(@client.webhook_endpoints) do |w|
        fixture_record?(w["description"]) || fixture_record?(w["url"])
      end
    end

    def stale_records(resource, &)
      matching = list_all(resource).select(&)
      matching.map { |r| r["id"] }
    end

    def fixture_record?(value)
      value.to_s.include?(FIXTURE_TAG)
    end

    # Walks every page of a list endpoint up to a sane safety cap.
    # Stops at 10 pages (1000 records) so a runaway entity never
    # blocks the seed forever.
    def list_all(resource)
      results = []
      page = resource.list(limit: 100)
      pages_seen = 0
      while page && pages_seen < 10
        results.concat(page.data)
        pages_seen += 1
        page = page.next
      end
      results
    end

    def delete_each(ids)
      return if ids.nil? || ids.empty?

      ids.each do |id|
        yield(id)
        log "  ✓ deleted #{id}"
      rescue Manza::Error => e
        log "  ! failed to delete #{id}: #{e.class.name.split("::").last}: #{e.message}"
      end
    end

    def try_delete_customer(id)
      @client.customers.delete(id)
    rescue Manza::ValidationError => e
      # Customers with invoices cannot be hard-deleted. Drop the fixture
      # tag instead, so the next seed does not count it as stale, and free
      # the email (unique per entity) the customers#update spec sets.
      log "  - customer #{id}: #{e.message} (retiring instead)"
      @client.customers.update(
        id, company_name: "Manza Fixture Co — retired #{id[0, 8]}", email: "fixture-retired-#{id}@example.com"
      )
    end

    def try_delete_invoice(id)
      # Only draft invoices can be deleted via the API. Sent/paid
      # ones stay around — the next seed run will create fresh drafts
      # and the lingering sent/paid ones will be rediscovered as
      # "stale" on the next teardown.
      @client.invoices.delete(id)
    rescue Manza::ValidationError, Manza::ForbiddenError => e
      log "  - invoice #{id}: #{e.message} (cancelling instead)"
      @client.invoices.cancel(id)
    end

    def try_cancel_payment_link(id)
      @client.payment_links.cancel(id)
    rescue Manza::Error => e
      log "  - payment link #{id}: #{e.message}"
    end

    # --- Output -------------------------------------------------------------

    def emit_env_block
      missing = EMITTED_KEYS.reject { |k| @ids.key?(k) }
      unless missing.empty?
        warn "::error:: Seed completed but #{missing.size} ID(s) missing: #{missing.join(", ")}"
        exit 1
      end

      puts
      puts "# Fixture IDs (also written to .env):"
      puts
      EMITTED_KEYS.each { |k| puts "#{k}=#{@ids.fetch(k)}" }
      puts

      write_env_file!
    end

    # Rewrites every EMITTED_KEYS line in .env (preserving everything
    # else — comments, MANZA_STAGING_API_KEY, MANZA_FIXTURE_ACCOUNT_ID,
    # etc.). If a key is missing from .env, it gets appended. This
    # lets `rake fixtures:record` chain teardown → seed → spec without
    # any manual paste step in between.
    def write_env_file!
      env_path = File.expand_path("../../.env", __dir__)
      unless File.exist?(env_path)
        warn ".env not found at #{env_path} — skipping in-place update."
        return
      end

      lines = File.readlines(env_path)
      seen = {}

      updated = lines.map do |line|
        if (match = line.match(/\A(#{EMITTED_KEYS.join("|")})=/o))
          key = match[1]
          seen[key] = true
          "#{key}=#{@ids.fetch(key)}\n"
        else
          line
        end
      end

      EMITTED_KEYS.each do |k|
        next if seen[k]

        updated << "#{k}=#{@ids.fetch(k)}\n"
      end

      File.write(env_path, updated.join)
      log "Wrote #{EMITTED_KEYS.size} fixture IDs to .env."
    end

    def random_client_reference(kind)
      "#{fixture_marker(kind.tr("_", "-"))}-#{SecureRandom.hex(6)}"
    end

    # A 24-digit Moroccan RIB: bank (3) + city (3) + account (16) + key (2),
    # with key = 97 - (first 22 digits * 100 mod 97).
    def random_rib
      body = "007780#{Array.new(16) { rand(10) }.join}"
      key = 97 - ((Integer(body, 10) * 100) % 97)
      format("%<body>s%<key>02d", body: body, key: key)
    end

    def random_ice_number
      # MA market requires 15 digits when business + ice_number is
      # present. We always send exactly 15 digits to keep validation
      # happy across markets.
      Array.new(15) { rand(10) }.join
    end
  end
  # rubocop:enable Metrics/ClassLength

  # Minimal HTTP receiver for the authorizer endpoint's tunnel. Verifies
  # each delivery with Manza::Webhook.verify? (so every record run proves
  # the shipped verifier) and records `payment.authorization_requested`
  # challenges by payment id. Runs on a background thread until the
  # process exits.
  class AuthorizationReceiver
    EVENT = "payment.authorization_requested"

    def self.start(port:, secret:)
      new(port:, secret:).tap(&:start)
    end

    def initialize(port:, secret:)
      require "socket"
      require "manza"
      @server = TCPServer.new("127.0.0.1", port)
      @secret = secret
      @challenges = {}
      @mutex = Mutex.new
    end

    def start
      Thread.new do
        loop { handle(@server.accept) }
      end
    end

    # Returns { payment_id => { "authorization_id", "nonce" } } once
    # every id has arrived.
    def wait_for(payment_ids, timeout:)
      deadline = Time.now + timeout
      loop do
        found = @mutex.synchronize { @challenges.slice(*payment_ids) }
        return found if found.size == payment_ids.size
        if Time.now > deadline
          raise "Timed out waiting for #{EVENT} webhooks for #{(payment_ids - found.keys).join(", ")} — is the tunnel up?"
        end

        sleep 1
      end
    end

    private

    def handle(socket)
      headers, body = read_request(socket)
      unless signed?(headers, body)
        warn "[fixtures] receiver: rejected a delivery (bad signature, or timestamp more than " \
             "#{Manza::Webhook::DEFAULT_TOLERANCE}s from this clock)"
        respond(socket, 401)
        return
      end

      record(JSON.parse(body))
      respond(socket, 200)
    rescue StandardError => e
      warn "[fixtures] receiver: #{e.class}: #{e.message}"
      respond(socket, 400)
    ensure
      socket.close
    end

    def read_request(socket)
      socket.gets # request line
      headers = {}
      while (line = socket.gets) && line != "\r\n"
        name, value = line.split(":", 2)
        headers[name.strip.downcase] = value.to_s.strip
      end
      [headers, socket.read(headers.fetch("content-length", "0").to_i)]
    end

    def signed?(headers, body)
      signature = headers["x-manza-signature"] || headers["x-zazu-signature"]
      timestamp = headers["x-manza-timestamp"] || headers["x-zazu-timestamp"]
      Manza::Webhook.verify?(payload: body, signature: signature, timestamp: timestamp, secret: @secret)
    end

    def record(payload)
      return unless payload["event"] == EVENT

      data = payload.fetch("data")
      @mutex.synchronize do
        @challenges[data.dig("payment", "id")] = {
          "authorization_id" => data.dig("authorization", "id"),
          "nonce" => data.dig("authorization", "nonce")
        }
      end
    end

    def respond(socket, status)
      socket.write("HTTP/1.1 #{status} #{status == 200 ? "OK" : "Error"}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
    rescue IOError, SystemCallError
      nil
    end
  end

  # The staging fixture state that `sdk_fixtures_ensure` keeps in place
  # (AGENTS.md → Staging fixture state), and the record preflight. The
  # MCP gateway's Google sign-in happens in the agent session, never in
  # this process: here we only build the tool's arguments and check the
  # one thing the public API shows, the authorizer's status.
  module StagingState
    STATE_FILE = File.expand_path("staging_fixture_state.json", __dir__)
    # A key_prefix: the first 16 characters of the raw key, not a secret.
    PREFIX_LENGTH = 16
    KEYS = { "creator" => "MANZA_STAGING_API_KEY", "authorizer" => "MANZA_STAGING_AUTHORIZER_API_KEY" }.freeze
    # ma.manza.dev is dual-stack: allow the machine's IPv4 and the /64 its
    # rotating IPv6 privacy addresses live in. Each host has records in one
    # family only, so it answers with that family's address.
    LOOKUPS = { "api.ipify.org" => 32, "api6.ipify.org" => 64 }.freeze
    FIX = "run sdk_fixtures_ensure (AGENTS.md → Staging fixture state)"

    module_function

    def ensure_arguments(env = ENV)
      missing = KEYS.values.select { |k| env.fetch(k, "").empty? }
      abort "Missing required env vars: #{missing.join(", ")}" unless missing.empty?

      cidrs = cidrs(env)
      desired = JSON.parse(File.read(STATE_FILE)).merge("creator_key_cidrs" => cidrs, "authorizer_key_cidrs" => cidrs)
      KEYS.to_h { |role, var| ["#{role}_key_prefix", env.fetch(var)[0, PREFIX_LENGTH]] }.merge("desired" => desired)
    end

    def cidrs(env)
      override = env.fetch("CIDR", "").split(",").map(&:strip).reject(&:empty?)
      return override unless override.empty?

      found = LOOKUPS.filter_map { |host, prefix| public_cidr(host, prefix) }
      abort "Could not look up this machine's public address: pass CIDR=<address>[,<address>]" if found.empty?
      found
    end

    # Direct, never through an env proxy: the proxy's egress is not this
    # machine. The preflight goes direct too, from the address allowlisted here.
    def public_cidr(host, prefix)
      body = Net::HTTP.start(host, 443, nil, use_ssl: true, open_timeout: 5, read_timeout: 5) { |http| http.get("/").body }
      address = IPAddr.new(body.strip)
      family = prefix == 32 ? "IPv4" : "IPv6"
      return "#{address.mask(prefix)}/#{prefix}" if address.ipv4? == (prefix == 32)

      warn "[fixtures] #{host} answered #{address}: no #{family} to allowlist"
    rescue SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError, IPAddr::InvalidAddressError => e
      warn "[fixtures] #{host}: #{e.class}: #{e.message}"
    end

    # Fails before teardown deletes anything when the authorizer is not
    # active. It cannot see the new-payee toggle; ensure covers that.
    def preflight!(env = ENV)
      missing = %w[MANZA_STAGING_URL MANZA_STAGING_AUTHORIZER_API_KEY].select { |k| env.fetch(k, "").empty? }
      abort "Missing required env vars: #{missing.join(", ")}" unless missing.empty?

      status, reason = authorizer_state(read_authorizer(env))
      return if status == "active"

      fix = status == "HTTP 401" ? "check MANZA_STAGING_AUTHORIZER_API_KEY in .env" : FIX
      abort "authorizer #{status}/#{reason || "none"}: #{fix}"
    end

    def read_authorizer(env)
      uri = URI.join(env.fetch("MANZA_STAGING_URL"), "/api/transfer_authorizer")
      abort "MANZA_STAGING_URL must be https: the preflight sends the authorizer key" unless uri.scheme == "https"

      request = Net::HTTP::Get.new(uri, "Authorization" => "Bearer #{env.fetch("MANZA_STAGING_AUTHORIZER_API_KEY")}",
                                        "Accept" => "application/json")
      Net::HTTP.start(uri.host, uri.port, nil, use_ssl: true, open_timeout: 10, read_timeout: 10) do |http|
        http.request(request)
      end
    rescue URI::Error, SocketError, SystemCallError, Timeout::Error, IOError, OpenSSL::SSL::SSLError => e
      abort "authorizer unreachable/#{e.class}: #{e.message}: check MANZA_STAGING_URL and the network"
    end

    # [status, reason]: the authorizer's own on a 200, else the HTTP status
    # and the API error's type.
    def authorizer_state(response)
      body = parse_json(response.body)
      case response.code.to_i
      when 200 then [body["status"], body["suspension_reason"]]
      when 404 then ["not enrolled (HTTP 404)", nil]
      else ["HTTP #{response.code}", (body["error"]["type"] if body["error"].is_a?(Hash))]
      end
    end

    def parse_json(text)
      parsed = JSON.parse(text.to_s)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end
end

namespace :fixtures do
  desc "Abort unless the staging transfer authorizer is active (runs before seed and record)"
  task :preflight do
    Fixtures::StagingState.preflight!
  end

  namespace :staging do
    desc "Print sdk_fixtures_ensure arguments as JSON (CIDR=<a>[,<b>] overrides the address lookup)"
    task :ensure_arguments do
      puts JSON.pretty_generate(Fixtures::StagingState.ensure_arguments)
    end
  end

  desc "Create fixture records on staging and print .env-paste-ready IDs"
  task seed: :preflight do
    Fixtures::Seeder.new.run!
  end

  desc "Delete every fixture record previously created on staging by this seed"
  task :teardown do
    Fixtures::Seeder.new.teardown!
  end
end
