# Zazu Ruby SDK

Ruby SDK for the [Manza API](https://ma.manza.finance). Faraday + HTTPX adapter for HTTP/2 + persistent connections.

```ruby
gem "zazu-ruby"
```

The gem is published as `zazu-ruby` on RubyGems but loaded as `zazu` in code (the `zazu` name was already taken by an unrelated 2014-era gem).

## Quick start

```ruby
require "zazu"

zazu = Zazu.new(api_key: ENV["ZAZU_API_KEY"])
# Or with explicit base URL (defaults to https://ma.manza.finance, Morocco):
zazu = Zazu.new(api_key: ENV["ZAZU_API_KEY"], base_url: "https://za.manza.finance")

entity = zazu.entity.get
# => #<Zazu::Response status=200 ...>
entity.body["name"]
# => "Acme Corp"
```

Environment variables `ZAZU_API_KEY`, `ZAZU_BASE_URL`, `ZAZU_API_VERSION`, and `ZAZU_TIMEOUT` are read by default.

## Resources

```ruby
zazu.entity.get

zazu.accounts.list(currency_code: "MAD", limit: 50)
zazu.accounts.get("019dde7d-...")
zazu.accounts.list_transactions("019dde7d-...", operation: "credit")
zazu.accounts.get_transaction("019dde7d-...", "01a0e1...")

zazu.customers.list(q: "acme")
zazu.customers.get("01a0...")
zazu.customers.create(
  customer_type: "business",
  company_name: "Acme Corp",
  email: "billing@acme.com",
  ice_number: "000000000000000"
)
zazu.customers.update("01a0...", email: "new@example.com")
zazu.customers.delete("01a0...")

zazu.invoices.list(status: "sent", limit: 50)
zazu.invoices.create(
  customer_id: "01a0...",
  currency_code: "MAD",
  issue_date: "2026-05-03",
  due_date: "2026-06-03",
  items: [{ description: "Consulting", quantity: 10, unit_price: "150.00" }]
)
zazu.invoices.send_invoice("01a0...")
zazu.invoices.mark_as_paid("01a0...")
zazu.invoices.cancel("01a0...")
zazu.invoices.credit_note("01a0...")
zazu.invoices.create_payment_link("01a0...", account_id: "019dde7d-...")

zazu.payment_links.list(status: "active")
zazu.payment_links.create(
  account_id: "019dde7d-...",
  amount: "1500.00",
  description: "March consulting",
  link_type: "single"
)
zazu.payment_links.cancel("01a0...")

zazu.checkout_sessions.create(
  account_id: "019dde7d-...",
  amount: "1500.00",
  success_url: "https://merchant.example.com/success?session_id={CHECKOUT_SESSION_ID}",
  cancel_url: "https://merchant.example.com/cancel",
  customer_email: "buyer@example.com",
  metadata: { order_id: "ORD-123" }
)
zazu.checkout_sessions.get("cs_...")

zazu.beneficiaries.list
zazu.beneficiaries.create(beneficiary_type: "business", company_name: "Acme Supplies", email: "ap@acme.com")
zazu.beneficiaries.list_external_accounts("01a0...")
zazu.beneficiaries.get_external_account("01a0...", "01a1...")
zazu.beneficiaries.create_external_account("01a0...", account_number: "007780...", name: "Main account")

zazu.payee_trust_requests.create(external_account_ids: ["01a1..."])
zazu.payee_trust_requests.get("01a2...")

zazu.transfer_drafts.create(
  account_id: "019dde7d-...",
  beneficiary_id: "01a0...",
  amount: "2500.00",
  client_reference: "po_1042" # unique per entity; a duplicate raises Zazu::ConflictError
)
zazu.transfer_drafts.get("01a3...")
zazu.transfer_drafts.decline("01a3...", authorization_id: "01a4...", reason: "Not ours")

zazu.webhook_endpoints.list
zazu.webhook_endpoints.create(
  url: "https://example.com/webhooks/zazu",
  events: ["invoice.sent", "payment_link.paid"]
)
zazu.webhook_endpoints.test_endpoint("01a0...")
zazu.webhook_endpoints.regenerate_secret("01a0...")
zazu.webhook_endpoints.enable("01a0...")
zazu.webhook_endpoints.disable("01a0...")
```

## Machine-authorized transfers

A draft inside your entity's authorization envelope (trusted payee, within limits) is sent to your enrolled authorizer endpoint as a `payment.authorization_requested` webhook carrying an `authorization.id` and a one-time `nonce`. Sign the draft from **your own record** of it with the endpoint's signing secret, and authorize it with a **different API key** from the one that created it (the creating key gets 403 `same_key_forbidden`):

```ruby
input = Zazu::TransferAuthorization.signature_input(
  payment_id: draft["id"],
  nonce: webhook["data"]["authorization"]["nonce"],
  amount: draft["amount"],               # the API's decimal string, e.g. "2500.0"
  currency_code: draft["currency_code"],
  account_id: draft["account_id"],
  payee: Zazu::TransferAuthorization.payee_for(external_account_id: draft["external_account_id"]),
  client_reference: draft["client_reference"]
)
signature = Zazu::TransferAuthorization.sign(secret: signing_secret, signature_input: input)

authorizer = Zazu.new(api_key: ENV["ZAZU_AUTHORIZER_API_KEY"])
authorizer.transfer_drafts.authorize(draft["id"], authorization_id: webhook["data"]["authorization"]["id"], signature: signature)
```

A wrong signature raises `Zazu::ValidationError` (`type` `invalid_signature`). Five on one challenge send the draft to your in-app approvers; five in a row suspend the authorizer.

## Pagination

Every list endpoint returns a `Zazu::Page`. The SDK enforces a hard cap of **100 records per page** — there is no auto-pagination across pages.

```ruby
page = zazu.invoices.list(limit: 100)
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

Every non-2xx response raises a subclass of `Zazu::Error`:

| Status | Class |
|---|---|
| 401 | `Zazu::AuthenticationError` |
| 403 | `Zazu::ForbiddenError` |
| 400 | `Zazu::ValidationError` (malformed request, e.g. bad `limit`/`cursor`) |
| 404 | `Zazu::NotFoundError` |
| 409 | `Zazu::ConflictError` (carries `#payment_id` for a duplicate `client_reference`) |
| 422 | `Zazu::ValidationError` |
| 429 | `Zazu::RateLimitError` (carries `#retry_after`) |
| 5xx | `Zazu::ServerError` |
| network | `Zazu::ConnectionError` |

Each error exposes `#status`, `#request_id`, `#type`, `#param`, and the raw `#body`.

```ruby
begin
  zazu.invoices.get("does-not-exist")
rescue Zazu::NotFoundError => e
  e.status      # => 404
  e.request_id  # => "req_..."
  e.type        # => "not_found_error"
end
```

## Versioning the API contract

```ruby
zazu = Zazu.new(api_key: "...", api_version: "2026-03-27")
```

Or via env: `ZAZU_API_VERSION=2026-03-27`. The header is sent on every request; the API echoes it back in both `Zazu-Version` and `Manza-Version`.

## Development

```bash
bundle install
bundle exec rspec
bundle exec rubocop
```

The spec suite is VCR-backed — cassettes live in `spec/fixtures/cassettes/` and are committed to the repo.

To re-record cassettes against staging:

```bash
cp .env.example .env
# fill in the keys, ZAZU_FIXTURE_ACCOUNT_ID and ZAZU_FIXTURE_BENEFICIARY_ID
cloudflared tunnel --config ~/.cloudflared/zazu-sdk-authorizer.yml run zazu-sdk-authorizer   # separate terminal
bundle exec rake fixtures:record
```

Recording executes a real 10.00 MAD transfer on staging (the authorize cassette). The one-time staging setup (keys, authorizer enrolment, trusted payee) is listed at the top of `lib/tasks/fixtures.rake`.

### The authorizer tunnel

The machine-authorization cassettes need the `payment.authorization_requested` webhook, which staging sends to the webhook endpoint enrolled as transfer authorizer. During `rake fixtures:record` the seeder listens for it on `127.0.0.1:${ZAZU_STAGING_AUTHORIZER_PORT:-4599}`, so a tunnel must forward the endpoint's public URL to that port. The endpoint URL cannot change once enrolled, so the tunnel needs a **stable hostname** (a throwaway `trycloudflare.com` URL won't do).

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

The tunnel's `service` port must match `ZAZU_STAGING_AUTHORIZER_PORT`: if you change one, change the other, or deliveries never reach the seeder and `fixtures:record` times out waiting for them.

Check it end to end: with the tunnel running and nothing on port 4599, `curl -X POST https://sdk-authorizer.manza.dev/` returns 502. During a record run the seeder answers unsigned requests with 401.

Cassettes are scrubbed before write — bearer tokens and request IDs are rewritten to placeholders. Even if a real key is in `.env`, the committed cassette never contains it.

## Cassettes for other-language SDKs

Each release of `zazu-ruby` publishes the cassette directory as a tarball release asset:

```
https://github.com/getzazu/zazu-ruby/releases/download/v0.1.0/cassettes-v0.1.0.tar.gz
```

`zazu-go`, `zazu-python`, etc. pin a specific version in their `.zazu-fixtures` file and download the tarball during CI. This guarantees every SDK is tested against the same recorded API interactions, surfacing cross-SDK inconsistencies immediately.

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
