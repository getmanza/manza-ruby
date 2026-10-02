# Plan 1 — API sync (0.3.0): Ruby first, then every SDK + CLI

Status: **shipped** — zazu-ruby and every SDK released 0.3.0 on 2026-10-02; the CLI (getmanza/cli#14) is still open. Baseline: the SDKs synced to app `aa4361e1c3` (2026-07-16). This plan covers app changes through `c07b99b7e1` (2026-10-02).

## Decisions taken

| Decision | Choice |
|---|---|
| 409 `duplicate_client_reference` | New 10th error class `ConflictError` exposing `payment_id`; 400 maps to `ValidationError` |
| Machine-authorization cassettes | Record the full happy path (authorize 200, decline 200, trust request 201) |
| Wire names | Keep this release additive: still `Zazu-Version`, `staging.zazu.ma`, `ZAZU_*` env, `Zazu` namespace. Everything Manza-named lands in Plan 2 |
| Payments vs transfer_drafts | Keep `transfer_drafts` (the alias is permanent server-side) and add `authorize`/`decline` to it. Renaming to `payments` is a Plan 2 break |
| Webhook signature verifier | **Out of scope.** Only the transfer-authorization signer ships |

Cost of the chosen order: the cassettes get recorded twice (here, then again in Plan 2 against `ma.manza.dev` / `Manza-Version`).

## What changed server-side (SDK-relevant only)

Nothing the SDK calls today was removed or renamed.

### New endpoints

| Method / path | Scope | Notes |
|---|---|---|
| `POST /api/beneficiaries` | `beneficiaries:write` | `person_name`, `company_name`, `email`, `beneficiary_type`, `phone_number`. Non-string values return 400. Shares the 10/min `recipient-creation` limit |
| `GET /api/beneficiaries/:id/external_accounts` (+ `/:ext_id`) | `beneficiaries:read` | Paginated. Items: `{id,name,account_number,bank_identifier,currency_code,default}` |
| `POST /api/beneficiaries/:id/external_accounts` | `beneficiaries:write` | `account_number` required. `bank_identifier` is required in ZA and forbidden in MA. Optional `name`, `country_code`, `currency_code`, `account_type` (`bank` only) |
| `POST /api/transfer_drafts/:id/authorize` | `transfers:authorize` | `authorization_id` and `signature` (hex). Must use a **different key** than the creator, otherwise 403 `same_key_forbidden` |
| `POST /api/transfer_drafts/:id/decline` | `transfers:authorize` | `authorization_id`, optional `reason`. Returns 200 `{id,status:"declined",expires_at,authorized_at,declined_at}` |
| `POST /api/payee_trust_requests` | `beneficiaries:request_trust` | `external_account_ids` (at most 100). Returns 201 `{id,status,external_account_ids,created_at,resolved_at}` |
| `GET /api/payee_trust_requests/:id` | `request_trust` or `beneficiaries:read` | `status` is one of pending, approved, declined, cancelled |

### Changes to existing endpoints

- `transfer_drafts.create` takes a new optional `client_reference` (unique per entity, at most 128 characters). A duplicate returns 409 `duplicate_client_reference` with `error.payment_id`. The response gains `client_reference` and `authorization {id,status,expires_at}|null`.
- `checkout_sessions.create` gains `customer_name`, `collect_billing_address` and `billing_address`. The response gains `settled_at` and `transaction{...}`, and a new status `clearing`.
- `payment_links.create` gains `collect_billing_address` and `billing_address`. The response gains `settled_at` and the status `clearing`.
- `customers` gain `registration_number` and `vat_number`. Market-gated keys (`tax_id`, `ice_number`, and `delivery_date` on invoices) are **absent** outside MA.
- Invoice `tax_rate` must be the issuer's rate or 0, otherwise 422.
- `webhook_endpoints.delete` is now a soft delete (still 204). `update(url:)` and `regenerate_secret` on an enrolled authorizer endpoint return 422.
- Lists return 400 for a malformed `limit`/`cursor`.
- The error envelope gains an optional `error.payment_id`.
- The response echoes both `Zazu-Version` and `Manza-Version`.

### Signing (authorize)

```
input = "manza.transfer-authorization.v1|<payment_id>|<nonce>|<amount>|<currency_code>|<account_id>|<payee>|<client_reference or "">"
payee = "ext:<external_account_id>" | "own:<destination_account_id>"
amount = server's string verbatim (e.g. "2500.0")
signature = hex(HMAC-SHA256(authorizer_endpoint.signing_secret, input))
```

- The nonce arrives only in the `payment.authorization_requested` webhook. That webhook also carries `signature_input`.
- There is no timestamp. Replay is prevented by the one-time nonce plus a 1h TTL.
- 5 bad signatures fail the challenge. 5 consecutive bad signatures suspend the authorizer.

## Phase A — zazu-ruby 0.3.0 (TDD, one PR)

Each step: write the spec first (cassette or unit), then implement, then run `bundle exec rake default`.

1. **Errors.**
   - `ConflictError < Error` with `attr_reader :payment_id`.
   - `ERROR_BY_STATUS`: add `400 => ValidationError` and `409 => ConflictError`.
   - Fill in `payment_id` from `error.payment_id`.
   - Unit specs in `spec/zazu/client_spec.rb` using WebMock stubs.
2. **`TransferDrafts`.**
   - Update the docs for `client_reference`.
   - Add `authorize(id, authorization_id:, signature:)`. It raises `Zazu::ArgumentError` locally when `signature` is blank: the server counts a missing signature as a failed attempt.
   - Add `decline(id, authorization_id:, reason: nil)`.
3. **`Zazu::TransferAuthorization`** (new file, pure functions, no HTTP).
   - `signature_input(payment_id:, nonce:, amount:, currency_code:, account_id:, payee:, client_reference: nil)` builds the input from the caller's *own* record of the payment. The point is that the caller checks the request against what it intended, rather than blindly signing the server's `signature_input`.
   - `sign(secret:, signature_input:)` returns the hex HMAC.
   - `payee_for(external_account_id:/destination_account_id:)`.
   - Unit spec with a fixed vector taken from the app's docs page / `PaymentAuthorization` spec, so every SDK can reuse the same vector.
4. **`Beneficiaries`.**
   - Add `create(**attrs)`, `list_external_accounts(beneficiary_id, limit:, cursor:)`, `get_external_account(beneficiary_id, id)` and `create_external_account(beneficiary_id, **attrs)`.
   - Fix the "created in the dashboard" docstring.
5. **`PayeeTrustRequests`** (new resource with a `client.payee_trust_requests` accessor): `create(external_account_ids:)` and `get(id)`.
6. **Docs-only touch-ups** for the checkout session and payment link params and statuses (the SDK is pass-through, so no code change). Update the README resource table and the CHANGELOG.
7. **VCR** (`spec/support/vcr.rb`):
   - Scrub the `Manza-Version` response header to `<ZAZU_VERSION>`.
   - Add `"account_number" => "<ACCOUNT_NUMBER>"` and `"bank_identifier" => "<BANK_IDENTIFIER>"` to `SENSITIVE_FIELD_PLACEHOLDERS`. **Blocking:** `list_external_accounts` on the discovered beneficiary returns real staging bank numbers, and only `rib` is scrubbed today.
   - Add the new external-account IDs to the fixture-ID table, so that the list scrubber keeps only fixture rows.
   - `signature` is in the *request* body, so scrub it with a `filter_sensitive_data` entry. The field map only covers response bodies. `nonce` never appears in an API response.

### Fixture seeding and recording (`lib/tasks/fixtures.rake`)

**One-time manual staging setup (done by you in the staging UI on `staging.zazu.ma`):**

1. Turn on the flags `release_api_transfers` and `release_api_webhook_authorization` for the fixture entity.
2. Give the existing `ZAZU_STAGING_API_KEY` these extra scopes: `beneficiaries:write`, `beneficiaries:request_trust`.
3. Create a **second** key, `ZAZU_STAGING_AUTHORIZER_API_KEY`, with `transfers:authorize`. Its creator must be an active member with payment authorize and delete permissions.
4. Create a webhook endpoint pointing at a stable tunnel URL (e.g. `cloudflared`/`ngrok` reserved domain), enrol it as the transfer authorizer with limits that cover 1.00 MAD, and store its secret as `ZAZU_STAGING_AUTHORIZER_SECRET`.
5. Mark the discovered beneficiary's bank account (`ZAZU_FIXTURE_BENEFICIARY_ID`) as a trusted payee. Make it an entity-owned account so the 1.00 MAD per re-record comes back. Make sure the fixture account has a balance.

**Seeder additions:**

- Create a fixture beneficiary via the API: `ZAZU_FIXTURE_CREATED_BENEFICIARY_ID`, `company_name` tagged with `FIXTURE_TAG`.
- Create its bank account: `ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID`, using the 24-digit MA RIB test value.
- Create a trust request for that fresh account: `ZAZU_FIXTURE_PAYEE_TRUST_REQUEST_ID`. It stays `pending`; nobody approves it.
- Machine path:
  - The envelope requires a **trusted payee**, confirmed in `api/payments/initiate_service.rb#route` and `TransferAuthorizer`.
  - So the machine-path drafts target the existing *discovered* beneficiary (`ZAZU_FIXTURE_BENEFICIARY_ID`). Its bank account is marked trusted once, by hand, in the one-time setup (add this as step 5 there) and stays trusted across re-records.
  - Freshly seeded beneficiaries are never trusted, so `fixtures:record` stays human-free.
- Create three drafts with a `client_reference`: authorizable, declinable, and bad-signature.
  - `ZAZU_FIXTURE_AUTHORIZABLE_DRAFT_ID`
  - `ZAZU_FIXTURE_DECLINABLE_DRAFT_ID`
  - `ZAZU_FIXTURE_BAD_SIGNATURE_DRAFT_ID`
- A tiny `TCPServer` receiver inside the rake task captures `payment.authorization_requested` payloads.
  - It verifies `X-Zazu-Signature`/`X-Manza-Signature` against the authorizer secret.
  - It writes `{authorization_id, nonce}` per draft to `.env` as `ZAZU_FIXTURE_*_AUTHORIZATION_ID` plus the nonce. The nonce is only needed at record time and is never committed.
  - The challenge TTL is 1h, so seed and record **must be the same `fixtures:record` run**.
- **Money moves.** Authorize 200 executes the transfer: every re-record sends 1.00 MAD from the fixture account to the trusted payee.
  - This breaks the current rake file's invariant ("seeding moves no money"), so update its comments.
  - The fixture account needs a balance, and the payee should be an entity-owned account so the money comes back.
- **Authorizer suspension.** 5 *consecutive* bad signatures across challenges suspend the authorizer, and only an in-app resume fixes that.
  - The bad-signature cassette uses its own draft and must record **before** the valid authorize, which resets the streak.
  - Do it in the rake task's sequence, or in an ordered example group (`:order => :defined`). Random spec order must never put it last.
- Teardown: there is no delete for beneficiaries, external accounts or trust requests. API-created ones stay inert, like drafts. Document this.

**Specs and cassettes (new):**

| Area | Cassettes |
|---|---|
| beneficiaries | create, list_external_accounts, get_external_account, create_external_account |
| payee_trust_requests | create, get |
| transfer_drafts | create with client_reference, duplicate → 409, authorize (200), decline (200), authorize with the same key → 403 `same_key_forbidden`, bad signature → 422 `invalid_signature` |

- Cassettes normally match on `method uri body`, but the authorize request body can't match on replay. At record time the signature is an HMAC over the real nonce with the real secret. On replay the spec computes it from placeholders, so the result differs.
- Fix: the two authorize cassettes use `match_requests_on: %i[method uri]`, and the recorded `signature` is scrubbed to `<SIGNATURE>`. Other SDKs then replay without needing the secret.
- Signer correctness is proven separately, by the fixed-vector unit spec.
- Re-record everything (`rake fixtures:record`), since response shapes changed (`client_reference`, `authorization`, `settled_at`, ...).
- `bundle exec rspec` must be green in replay-only mode.

**Release.**
- PR, then `fable-validator`, then merge.
- `bundle exec rake release[0.3.0]`.
- The cassette tarball `cassettes-v0.3.0.tar.gz` ships with it.

## Phase B — propagate (one PR per repo, start the same day as the release)

**Every consumer fetches the latest `v*` cassette tag unpinned, so releasing 0.3.0 changes all 7 CIs at once.** Open the consumer PRs immediately after the release, and expect replay failures until each one lands. The alternative is to pin `v0.2.1` in each fetch script first. Recommended: do not pin; the PRs land within a day.

Same checklist per SDK, mirroring the Ruby PR:

1. Add a `ConflictError` with `paymentId`/`payment_id`, and map 400 to Validation and 409 to Conflict.
2. Add `transferDrafts.authorize`/`decline`, which validates that the signature is present.
3. Add the `TransferAuthorization` signer, unit-tested with **the same fixed vector** as Ruby.
4. Add `beneficiaries.create` plus the three external-account methods.
5. Add the `payeeTrustRequests.create`/`get` resource.
6. Wherever the SDK models response types, add the new fields: TS types, Go structs, Rust structs, PHP/Crystal if typed. These include `client_reference`, `authorization`, `settled_at`, `transaction`, `billing_address`, `collect_billing_address`, `customer_name`, `registration_number`, `vat_number`, and the `clearing` status. Mark `tax_id`, `ice_number` and `delivery_date` optional.
7. Add the new `ZAZU_FIXTURE_*` placeholders to that SDK's fixture-ids table, matching Ruby's `spec/support/fixture_ids.rb` exactly.
8. Add replay tests for every new cassette. The authorize cassettes match on method plus URI.
9. Bump to 0.3.0, update the CHANGELOG, release via the existing workflow.

| Repo | Resource files | Notes |
|---|---|---|
| zazu-ts | `src/resources/*.ts`, `src/errors.ts` | Also fix the stale `src/version.ts` (0.1.0) while bumping |
| zazu-python | `src/zazu_sdk/resources/*.py` | |
| zazu-go | `resources.go`, `errors.go` | Also fix the stale `Version` const (0.1.0) |
| zazu-php | `src/Resources/*.php`, `src/Exception/` | Also fix the stale `VERSION` const (0.1.0) |
| zazu-rust | `src/resources/*.rs`, `src/error.rs` | |
| zazu-crystal | `src/zazu/resources/*.cr` | |
| zazu-elixir | `lib/zazu/*.ex` | |
| cli (`getmanza/cli`) | `bin/zazu.ts` | After zazu-ts 0.3.0: bump `@getzazu/sdk` to `^0.3.0`. Switch transfers/beneficiaries from `client.request` to the typed methods. Add the commands `beneficiaries create`, `beneficiaries accounts list/get/create`, `transfers create --client-reference`, `transfers authorize --authorization-id --signature`, `transfers decline`, `payee-trust-requests create/get`. Add the transfers/beneficiaries rows that are missing from the `CLAUDE.md` table. Release 0.3.0 (it also ships the unreleased "transfers + beneficiaries" commit) |

Order: Ruby, then (TS, Python, Go, PHP, Rust, Crystal, Elixir in parallel), then the CLI (it depends on TS).

## Verification

- Ruby: `bundle exec rake default` green in replay mode, `fable-validator` pass, `gem build` OK.
- Each SDK: its CI is green against `cassettes-v0.3.0`, and the signer vector test passes.
- Smoke test against staging with a real key, once per SDK (optional): `beneficiaries.list_external_accounts`.

## Risks

- **Authorize cassette determinism.** It depends on the custom matcher above. Validate on the Ruby PR before propagating.
- **Second key.** Staging needs a second key and an authorizer enrolment that survive re-records. If either gets rotated, `fixtures:record` breaks. Document both in `.env.example`.
- **ZA-only branches.** `bank_identifier` and the hidden-key behaviour are not recordable on MA staging. They are covered only by docs and comments.

