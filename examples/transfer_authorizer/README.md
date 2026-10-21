# Transfer authorizer example

Two processes and a shared ledger, matching the two-key model of [transfer authorization](https://ma.manza.finance/docs/api/transfer-authorization):

| File | Process | Key |
|---|---|---|
| `create_transfer.rb` | Creates a transfer draft, records it in `ledger.json` from the API's response | A (`transfers:write`) |
| `config.ru` / `authorizer.rb` | Receives `payment.authorization_requested`, verifies it, checks the ledger, signs and authorizes (or declines) | B (`transfers:authorize`) |
| `ledger.rb` | Your own record of what you created, keyed by `client_reference`. Swap it for your database | — |

## Setup

Do steps 1–6 of [Setup, step by step](../../README.md#setup-step-by-step) in the SDK README first: feature flags, keys A and B, a stable tunnel URL, the webhook endpoint, enrolment and a trusted payee.

```bash
cd examples/transfer_authorizer
bundle install
cp .env.example .env    # fill in both keys, the signing secret, the account and the beneficiary
```

## Run

Terminal 1, the authorizer (point your tunnel at the same port):

```bash
bundle exec rackup -p 4599
```

Terminal 2, the creator:

```bash
bundle exec ruby create_transfer.rb          # 10.00
bundle exec ruby create_transfer.rb 250.00   # any amount within your limits
```

## What each log line means

`create_transfer.rb`:

| Line | Meaning |
|---|---|
| `created payment … (client_reference …)` | The draft exists and is in `ledger.json` |
| `challenge sent, waiting for the authorizer` | The draft is inside your envelope: the webhook is on its way to terminal 1 |
| `sent to your approvers, not the authorizer` | The draft is outside the envelope (untrusted payee, over a limit, suspended, …). See Troubleshooting |
| `create failed: … (type …, request_id …)` | The API refused the draft. Quote the `request_id` to support |

The authorizer (`rackup`):

| Line | Meaning |
|---|---|
| `received payment.authorization_requested (…), signature verified` | The delivery's `X-Manza-Signature` matches and its timestamp is fresh |
| `rejected a delivery: …` | Bad signature, stale timestamp, missing header or non-JSON body: answered 401 |
| `ignoring …` | Any other event: answered 200, nothing done |
| `ledger match for …` | The draft's id, amount, currency, account and payee match `ledger.json` |
| `signature input differs from the webhook's: …` | The input built from the ledger is not the webhook's `signature_input`. The authorize that follows will fail with `invalid_signature`; compare the two strings |
| `signed the challenge for payment …` | HMAC-SHA256 of the ledger's signature input under the signing secret |
| `authorized payment … (status "processing")` | Done: the transfer executes |
| `declined payment …: <reason>` | The draft is not in the ledger, or differs from it. The draft is deleted |
| `API error …: … (type …, request_id …)` | Authorize or decline failed. Look the `type` up in the docs' errors table |

The authorizer answers the webhook with 200 straight away and does the ledger check, signing and authorize on a background thread: the delivery has a timeout, and a retried webhook is safe because authorize replays idempotently. It waits up to 10 seconds for the ledger entry, because the webhook can arrive before `create_transfer.rb` has written it.

## Troubleshooting

See the errors table and "Which transfers qualify" in the [transfer authorization docs](https://ma.manza.finance/docs/api/transfer-authorization).
