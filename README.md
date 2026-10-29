# Manza Ruby SDK

Ruby SDK for the [Manza API](https://ma.manza.finance). Faraday + HTTPX adapter for HTTP/2 + persistent connections.

```ruby
gem "manza"
```

Upgrading from `zazu-ruby` 0.x? See the migration guide in [CHANGELOG.md](CHANGELOG.md).

## Quick start

```ruby
require "manza"

manza = Manza.new(api_key: ENV["MANZA_API_KEY"])
# Or with explicit base URL (defaults to https://ma.manza.finance, Morocco):
manza = Manza.new(api_key: ENV["MANZA_API_KEY"], base_url: "https://za.manza.finance")

entity = manza.entity.get
# => #<Manza::Response status=200 ...>
entity.body["name"]
# => "Acme Corp"
```

Environment variables `MANZA_API_KEY`, `MANZA_BASE_URL`, `MANZA_API_VERSION`, and `MANZA_TIMEOUT` are read by default. The pre-1.0 `ZAZU_*` names still work for all of 1.x, with a one-time deprecation warning per variable.

## Resources

```ruby
manza.entity.get

manza.accounts.list(currency_code: "MAD", limit: 50)
manza.accounts.get("019dde7d-...")
manza.accounts.list_transactions("019dde7d-...", operation: "credit")
manza.accounts.get_transaction("019dde7d-...", "01a0e1...")

manza.customers.list(q: "acme")
manza.customers.get("01a0...")
manza.customers.create(
  customer_type: "business",
  company_name: "Acme Corp",
  email: "billing@acme.com",
  ice_number: "000000000000000"
)
manza.customers.update("01a0...", email: "new@example.com")
manza.customers.delete("01a0...")

manza.invoices.list(status: "sent", limit: 50)
manza.invoices.create(
  customer_id: "01a0...",
  currency_code: "MAD",
  issue_date: "2026-05-03",
  due_date: "2026-06-03",
  items: [{ description: "Consulting", quantity: 10, unit_price: "150.00" }]
)
manza.invoices.send_invoice("01a0...")
manza.invoices.mark_as_paid("01a0...")
manza.invoices.cancel("01a0...")
manza.invoices.credit_note("01a0...")
manza.invoices.create_payment_link("01a0...", account_id: "019dde7d-...")

manza.payment_links.list(status: "active")
manza.payment_links.create(
  account_id: "019dde7d-...",
  amount: "1500.00",
  description: "March consulting",
  link_type: "single"
)
manza.payment_links.cancel("01a0...")

manza.checkout_sessions.create(
  account_id: "019dde7d-...",
  amount: "1500.00",
  success_url: "https://merchant.example.com/success?session_id={CHECKOUT_SESSION_ID}",
  cancel_url: "https://merchant.example.com/cancel",
  customer_email: "buyer@example.com",
  metadata: { order_id: "ORD-123" }
)
manza.checkout_sessions.get("cs_...")

manza.beneficiaries.list
manza.beneficiaries.create(beneficiary_type: "business", company_name: "Acme Supplies", email: "ap@acme.com")
manza.beneficiaries.list_external_accounts("01a0...")
manza.beneficiaries.get_external_account("01a0...", "01a1...")  # "trusted": true once a trusted payee
manza.beneficiaries.create_external_account("01a0...", account_number: "007780...", name: "Main account")

manza.payee_trust_requests.create(external_account_ids: ["01a1..."])
manza.payee_trust_requests.get("01a2...")

manza.transfer_drafts.create(
  account_id: "019dde7d-...",
  beneficiary_id: "01a0...",
  amount: "2500.00",
  client_reference: "po_1042" # unique per entity; a duplicate raises Manza::ConflictError
)
manza.transfer_drafts.get("01a3...")            # authorization: status, refusal_reason
manza.transfer_drafts.decline("01a3...", authorization_id: "01a4...", reason: "Not ours")

manza.transfer_authorizer.get  # status, suspension_reason, limits, daily_authorized_total; NotFoundError: none enrolled

manza.webhook_endpoints.list
manza.webhook_endpoints.create(
  url: "https://example.com/webhooks/manza",
  events: ["invoice.sent", "payment_link.paid"]
)
manza.webhook_endpoints.test_endpoint("01a0...")
manza.webhook_endpoints.regenerate_secret("01a0...")
manza.webhook_endpoints.enable("01a0...")
manza.webhook_endpoints.disable("01a0...")
```

## Machine-authorized transfers

A draft inside your entity's authorization envelope (trusted payee, or a new one when you allow it, within limits) is sent to your enrolled authorizer endpoint as a `payment.authorization_requested` webhook carrying an `authorization.id` and a one-time `nonce`. Your system checks it against its own ledger, signs it and authorizes it with a **different API key** from the one that created it. [`examples/transfer_authorizer/`](examples/transfer_authorizer/) runs the whole flow.

### Setup, step by step

1. **Feature flags.** Ask support to enable API transfers and transfer authorization (`release_api_webhook_authorization`) on your workspace.
2. **Two API keys.** Key A creates drafts (`transfers:write`; `beneficiaries:request_trust` for step 6; `entity:read`, `accounts:read`, `webhook_endpoints:read` and `beneficiaries:read` for the preflight in step 7). Key B answers the challenges (`transfers:authorize`). The creating key is always refused with 403 `same_key_forbidden`, so keep key B and the signing secret on the system that holds your ledger. Bind key B to an IP allowlist: authorizing from a key without one is refused with 403 `unrestricted_api_key`. Bind key A to one too if you allow new payees (step 6): a draft to a new payee from a key without an allowlist goes to your approvers (`unrestricted_api_key`).
3. **A stable public URL.** Your authorizer needs an HTTPS URL that never changes: an enrolled endpoint's URL is locked. Use a reserved ngrok domain (`ngrok http --url=your-name.ngrok.app 4599`) or a named Cloudflare tunnel (see [The authorizer tunnel](#the-authorizer-tunnel)). Never a free ngrok URL: it changes on every restart.
4. **Create the webhook endpoint** at that URL:

   ```ruby
   manza.webhook_endpoints.create(url: "https://your-name.ngrok.app/", events: ["transfer.executed"])
   ```

5. **Enrol it in the app**: Settings → Developer → Transfer approval. Pick the endpoint, the currency and both limits, confirm with your two-factor code, and copy the signing secret: it is shown once.
6. **Allow new payees, or trust each payee.** Turn on *Approve transfers to new payees* at enrolment (or later, same page, with your two-factor code) and set the *Limit per transfer to a new payee*. Your authorizer may then approve a transfer to bank details your workspace never trusted, up to that limit, and its signature trusts them: the webhook's `payment.payee_trusted` is `false` for such a transfer. Bank details whose trust was revoked, or that were edited after trusting, still go to your approvers. Without the option, an approver marks the beneficiary's bank account as trusted from the Beneficiaries list, or you ask them to:

   ```ruby
   manza.payee_trust_requests.create(external_account_ids: ["01a1..."])
   ```

   `trusted` on `manza.beneficiaries.get_external_account` says which it is. The API does not show whether the option is on.
7. **Run the preflight, then the example** (from `examples/transfer_authorizer/`, after `bundle install` and filling in `.env`): `bundle exec ruby preflight.rb` checks what the API shows of steps 1–6 and prints a fix for each that fails. What it cannot see, check by hand: that key B is bound to an IP allowlist, and, for a payee not trusted yet, that *Approve transfers to new payees* is on and key A is bound to an IP allowlist too (it warns, it does not fail). Then `bundle exec rackup -p 4599` in one terminal, `bundle exec ruby create_transfer.rb` in another.
8. **Troubleshooting**: a draft that goes to your approvers instead has an `authorization` with status `refused` and a `refusal_reason` (`create_transfer.rb` prints it in words); `manza.transfer_authorizer.get` shows a suspension and its `suspension_reason`. An authorize answered 409 `authorization_busy` (a bank-detail edit or trust on the same payee was in flight) is safe to retry. The reasons, and an API error's `type`, are in the [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).

### Verifying the webhook

Pass the **raw request body**, never re-serialized JSON. `construct_event` reads `X-Manza-Signature` and `X-Manza-Timestamp` (any case, the Rack `HTTP_X_MANZA_*` form, or the legacy `X-Zazu-*` names), checks the signature in constant time and the timestamp within 5 minutes, and returns the parsed event (a Hash). It raises `Manza::ArgumentError` otherwise:

```ruby
begin
  event = Manza::Webhook.construct_event(payload: request.body.read, headers: request.env, secret: signing_secret)
rescue Manza::ArgumentError => e
  return [401, {}, [e.message]]
end
```

`Manza::Webhook.verify?(payload:, signature:, timestamp:, secret:)` returns a boolean instead. Both accept `tolerance: nil` to skip the timestamp check. Use it only to replay a captured delivery in a local tool or test, never on a live endpoint: without the check, anyone holding a captured delivery can replay it.

### Signing the challenge

Sign the draft from **your own record** of it with the endpoint's signing secret:

```ruby
input = Manza::TransferAuthorization.signature_input(
  payment_id: draft["id"],
  nonce: webhook["data"]["authorization"]["nonce"],
  amount: draft["amount"],               # the API's decimal string, e.g. "2500.0"
  currency_code: draft["currency_code"],
  account_id: draft["account_id"],
  payee: Manza::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"]),
  client_reference: draft["client_reference"]
)
signature = Manza::TransferAuthorization.sign(secret: signing_secret, signature_input: input)

authorizer = Manza.new(api_key: ENV["MANZA_AUTHORIZER_API_KEY"])
authorizer.transfer_drafts.authorize(draft["id"], authorization_id: webhook["data"]["authorization"]["id"], signature: signature)
```

A wrong signature raises `Manza::ValidationError` (`type` `invalid_signature`). Five on one challenge send the draft to your in-app approvers; five in a row suspend the authorizer.

## Pagination

Every list endpoint returns a `Manza::Page`. The SDK enforces a hard cap of **100 records per page** — there is no auto-pagination across pages.

```ruby
page = manza.invoices.list(limit: 100)
page.data         # => Array of invoice hashes
page.has_more     # => true / false
page.next_cursor  # => string or nil

# Walk pages explicitly:
while page
  page.data.each { |inv| process(inv) }
  page = page.next  # returns nil when has_more is false
end
```

For capped iteration, use the underlying `each_page_record` helper on a resource (private; access via `send` if you need it). The deliberate restriction is a guardrail — accidentally pulling 50,000 records in a single SDK call should be impossible without explicit per-page consent.

## Errors

Every non-2xx response raises a subclass of `Manza::Error`:

| Status | Class |
|---|---|
| 401 | `Manza::AuthenticationError` |
| 403 | `Manza::ForbiddenError` |
| 400 | `Manza::ValidationError` (malformed request, e.g. bad `limit`/`cursor`) |
| 404 | `Manza::NotFoundError` |
| 409 | `Manza::ConflictError` (carries `#payment_id` for a duplicate `client_reference`) |
| 422 | `Manza::ValidationError` |
| 429 | `Manza::RateLimitError` (carries `#retry_after`) |
| 5xx | `Manza::ServerError` |
| network | `Manza::ConnectionError` |

Each error exposes `#status`, `#request_id`, `#type`, `#param`, and the raw `#body`.

```ruby
begin
  manza.invoices.get("does-not-exist")
rescue Manza::NotFoundError => e
  e.status      # => 404
  e.request_id  # => "req_..."
  e.type        # => "not_found_error"
end
```

## Versioning the API contract

```ruby
manza = Manza.new(api_key: "...", api_version: "2026-03-27")
```

Or via env: `MANZA_API_VERSION=2026-03-27`. The header is sent on every request; the API echoes it back in `Manza-Version` (and the legacy `Zazu-Version`); `response.api_version` reads it.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

The spec suite is VCR-backed — cassettes live in `spec/fixtures/cassettes/` and are committed to the repo.

To re-record cassettes against staging:

```bash
bin/rename-env-vars    # upgrading an existing 0.x .env: ZAZU_* → MANZA_* (backup in .env.bak)
cp .env.example .env   # fresh setup only — overwrites an existing .env
# fill in the keys, MANZA_FIXTURE_ACCOUNT_ID and MANZA_FIXTURE_BENEFICIARY_ID
cloudflared tunnel --config ~/.cloudflared/zazu-sdk-authorizer.yml run zazu-sdk-authorizer   # separate terminal
bundle exec rake fixtures:record
```

Recording executes two real 10.00 MAD transfers on staging: the authorize cassette pays the trusted payee, and authorize_new_payee pays a freshly seeded bank account (and trusts it). The one-time staging setup (keys, authorizer enrolment, trusted payee, the new-payee option) is listed at the top of `lib/tasks/fixtures.rake`; AGENTS.md → Staging fixture state keeps it in place.

### The authorizer tunnel

The machine-authorization cassettes need the `payment.authorization_requested` webhook, which staging sends to the webhook endpoint enrolled as transfer authorizer. During `rake fixtures:record` the seeder listens for it on `127.0.0.1:${MANZA_STAGING_AUTHORIZER_PORT:-4599}`, so a tunnel must forward the endpoint's public URL to that port. The endpoint URL cannot change once enrolled, so the tunnel needs a **stable hostname** (a throwaway `trycloudflare.com` URL won't do).

The existing setup uses a named Cloudflare tunnel `zazu-sdk-authorizer` → `https://sdk-authorizer.manza.dev/`. To run it on a new machine:

```bash
brew install cloudflared
cloudflared tunnel login                    # pick the manza.dev zone
cloudflared tunnel token --cred-file ~/.cloudflared/zazu-sdk-authorizer.json zazu-sdk-authorizer
cat > ~/.cloudflared/zazu-sdk-authorizer.yml <<YML
tunnel: zazu-sdk-authorizer
credentials-file: $HOME/.cloudflared/zazu-sdk-authorizer.json
ingress:
  - hostname: sdk-authorizer.manza.dev
    service: http://127.0.0.1:4599
  - service: http_status:404
YML
cloudflared tunnel --config ~/.cloudflared/zazu-sdk-authorizer.yml run zazu-sdk-authorizer
```

To create one from scratch instead (then point a new webhook endpoint at it and enrol that one as authorizer):

```bash
cloudflared tunnel create zazu-sdk-authorizer
cloudflared tunnel route dns zazu-sdk-authorizer sdk-authorizer.manza.dev
```

The tunnel's `service` port must match `MANZA_STAGING_AUTHORIZER_PORT`: if you change one, change the other, or deliveries never reach the seeder and `fixtures:record` times out waiting for them.

Check it end to end: with the tunnel running and nothing on port 4599, `curl -X POST https://sdk-authorizer.manza.dev/` returns 502. During a record run the seeder answers unsigned requests with 401.

Cassettes are scrubbed before write — bearer tokens and request IDs are rewritten to placeholders. Even if a real key is in `.env`, the committed cassette never contains it.

## The SDK family

| SDK | Repository | Install |
|---|---|---|
| Ruby (reference implementation, records the cassettes) | [getmanza/manza-ruby](https://github.com/getmanza/manza-ruby) (this repo) | `gem "manza"` |
| TypeScript / JavaScript | [getmanza/manza-ts](https://github.com/getmanza/manza-ts) | `npm install @getmanza/sdk` |
| Python | [getmanza/manza-python](https://github.com/getmanza/manza-python) | `pip install manza` |
| Go | [getmanza/manza-go](https://github.com/getmanza/manza-go) | `go get github.com/getmanza/manza-go` |
| PHP | [getmanza/manza-php](https://github.com/getmanza/manza-php) | `composer require manza/manza-php` |
| Rust | [getmanza/manza-rust](https://github.com/getmanza/manza-rust) | `cargo add manza` |
| Crystal | [getmanza/manza-crystal](https://github.com/getmanza/manza-crystal) | shard `manza` (`github: getmanza/manza-crystal`) |
| Elixir | [getmanza/manza-elixir](https://github.com/getmanza/manza-elixir) | `{:manza, "~> 1.0"}` |
| CLI | [getmanza/cli](https://github.com/getmanza/cli) | `npm install -g @getzazu/cli` or `brew install getmanza/tap/zazu` |

## Cassettes for other-language SDKs

Each release of `manza-ruby` publishes the cassette directory as a tarball release asset:

```
https://github.com/getmanza/manza-ruby/releases/download/v1.0.0/cassettes-v1.0.0.tar.gz
```

`manza-go`, `manza-python`, etc. pin a specific tag in their cassette fetch script and download the tarball during CI. This guarantees every SDK is tested against the same recorded API interactions, surfacing cross-SDK inconsistencies immediately.

VCR's YAML format is supported natively by:

- Ruby — VCR (this gem)
- Go — go-vcr
- Python — VCR.py
- PHP — PHP-VCR
- Crystal — vcr-crystal / hi8.cr
- Rust — http_replayer (or a small custom YAML reader)
- JavaScript / TypeScript — Talkback or polly.js (slight format adapter needed)

## License

MIT
