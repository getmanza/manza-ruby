# Changelog

All notable changes to `manza` (formerly `zazu-ruby`) are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The SDK is renamed from Zazu to Manza and released as `manza` 1.0.0.
The API surface is otherwise unchanged.

### Migration from `zazu-ruby` 0.x

| Was | Now |
|---|---|
| `gem "zazu-ruby"` | `gem "manza"` |
| `require "zazu"` | `require "manza"` |
| `Zazu.new`, `Zazu::Client`, `Zazu::Error`, … | `Manza.new`, `Manza::Client`, `Manza::Error`, … |
| `ZAZU_API_KEY` | `MANZA_API_KEY` |
| `ZAZU_BASE_URL` | `MANZA_BASE_URL` |
| `ZAZU_API_VERSION` | `MANZA_API_VERSION` |
| `ZAZU_TIMEOUT` | `MANZA_TIMEOUT` |
| `Zazu-Version` request header | `Manza-Version` |
| User-Agent `zazu-ruby/x` | `manza-ruby/x` |

The `ZAZU_*` environment variables keep working for all of 1.x: when
the `MANZA_*` one is unset, the client reads the old name and prints a
one-time deprecation warning per variable.

### Changed

- Gem `zazu-ruby` → `manza`, namespace `Zazu` → `Manza`, repository
  `getmanza/zazu-ruby` → `getmanza/manza-ruby`.
- Requests send `Manza-Version` and User-Agent `manza-ruby/<version>`.
- `Response#api_version` reads `Manza-Version`, falling back to
  `Zazu-Version`.
- Cassettes use the placeholders `<MANZA_API_KEY>` and `<MANZA_VERSION>`
  (were `<ZAZU_API_KEY>`, `<ZAZU_VERSION>`). Other SDKs replaying them
  must rename their placeholders in lockstep.
- Fixture and staging env vars for recording are `MANZA_FIXTURE_*` and
  `MANZA_STAGING_*`, with no fallback. Rename them in your `.env`.

## [0.3.0]

### Added

- `Zazu::ConflictError` (409), the 10th error class. A duplicate
  `client_reference` on a transfer draft raises it with `#payment_id`
  naming the existing draft. 400 now maps to `Zazu::ValidationError`
  (lists return 400 for a malformed `limit`/`cursor`).
- `TransferDrafts#authorize(id, authorization_id:, signature:)` and
  `#decline(id, authorization_id:, reason: nil)` for machine-authorized
  transfers. A blank signature raises `Zazu::ArgumentError` locally —
  the API would count it as a failed attempt.
- `TransferDrafts#create` documents the new optional `client_reference`;
  responses carry `client_reference` and `authorization`.
- `Zazu::TransferAuthorization` — `signature_input`, `sign` and
  `payee_for`, the HMAC-SHA256 signer for authorization challenges, with
  a fixed test vector shared across SDKs
  (`spec/zazu/transfer_authorization_spec.rb`).
- `Beneficiaries#create`, `#list_external_accounts`,
  `#get_external_account` and `#create_external_account`.
- `Zazu::Resources::PayeeTrustRequests` (`zazu.payee_trust_requests`) —
  `create(external_account_ids:)` and `get(id)`.
- Docs for new pass-through fields: checkout session `customer_name`,
  `collect_billing_address`, `billing_address`, `settled_at`,
  `transaction` and the `clearing` status; payment link billing fields;
  customer `registration_number` / `vat_number` (and MA-only `tax_id` /
  `ice_number`).

### Changed

- Default base URL is now `https://ma.manza.finance` (Morocco production;
  South Africa is `https://za.manza.finance`). Cassettes are recorded
  against staging at `https://ma.manza.dev`. The old `zazu.ma` hosts are
  still served.
- Cassettes scrub `Manza-Version`, `account_number`, `bank_identifier`
  and the authorize request `signature`. The three authorize cassettes
  match the request body minus `signature` (`body_without_signature`),
  which replay cannot reproduce; other SDKs should do the same.
- `rake fixtures:seed` needs a second, authorizer API key, the
  authorizer endpoint's signing secret and a tunnel to a local webhook
  receiver (see the one-time setup in `lib/tasks/fixtures.rake`).
  Re-recording now executes a real 10.00 MAD transfer (the API minimum).
- Every cassette is re-recorded against `ma.manza.dev`, including the
  full machine-authorization path (authorize 200, decline 200, bad
  signature 422, same key 403, duplicate client_reference 409).

## [0.2.1]

### Added

- `Zazu::Resources::TransferDrafts` — `create` and `get`. Creating a
  draft routes it into the workspace's in-app approval flow; the API
  never executes a transfer itself. Lifecycle: `requested` →
  `processing` → `completed` / `failed`.
- `Zazu::Resources::Beneficiaries` — `list` and `get`, the read-only
  recipient directory (each beneficiary embeds its bank accounts;
  the `default` one is used when a transfer names only the
  beneficiary_id).
- Fixture seeding: `discover_beneficiary_id!` + `seed_transfer_draft!`.
  The transfer_drafts/beneficiaries cassettes in this release are
  hand-authored against the documented contract; re-record via
  `rake fixtures:record` once the endpoints are live on staging.

## [0.2.0]

### Added

- `Zazu::Resources::CheckoutSessions` — `create` and `get` for one-off
  hosted checkout sessions. Status enum: `open`, `processing`,
  `complete`, `expired` (read-only — no API to mutate). No list, no
  update, no delete; sessions are addressed by their `cs_…` id.

## [0.1.0]

Initial release.

### Added

- `Zazu::Client` — Faraday + HTTPX adapter, JSON request/response, retry middleware.
- Resource modules: `Accounts`, `Customers`, `Entity`, `Invoices`, `PaymentLinks`, `WebhookEndpoints`.
- Cursor-based pagination via `Zazu::Page` (max 100 records per page; no auto-pagination).
- Error hierarchy: `AuthenticationError`, `ForbiddenError`, `NotFoundError`,
  `ValidationError`, `RateLimitError`, `ServerError`, `ConnectionError`,
  `ConfigurationError`, `ArgumentError` — all under `Zazu::Error`.
- VCR-backed RSpec suite covering every public method.
- Cassette tarball published as a release asset for cross-language SDK reuse.
