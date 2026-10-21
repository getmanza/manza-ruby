# frozen_string_literal: true

require "spec_helper"
require "rack/mock"
require "logger"
require "stringio"
require "tmpdir"
require_relative "../../examples/transfer_authorizer/authorizer"

# Drives the example's authorizer with a signed copy of the documented
# `payment.authorization_requested` payload (getmanza/app
# WebhookEvents::PaymentAuthorizationRequested.example_payload, verbatim).
# WebMock only: no cassette, no network.
RSpec.describe TransferAuthorizer::App do
  let(:secret) { "whsec_example_authorizer_secret" }
  let(:base_url) { "https://staging.manza.example" }
  let(:draft_id) { "01958e51-7c5a-7000-8000-000000000012" }
  let(:authorization_id) { "01958e51-7c5a-7000-8000-000000000011" }
  let(:example_payload) do
    {
      "event" => "payment.authorization_requested",
      "event_id" => "01958e51-7c5a-7000-8000-000000000010",
      "created_at" => "2026-10-01T12:00:00Z",
      "data" => {
        "authorization" => {
          "id" => "01958e51-7c5a-7000-8000-000000000011",
          "nonce" => "9f86d081884c7d659a2feaa0c55ad015",
          "expires_at" => "2026-10-01T13:00:00Z",
          "signature_version" => "manza.transfer-authorization.v1"
        },
        "payment" => {
          "id" => "01958e51-7c5a-7000-8000-000000000012",
          "amount" => "2500.0",
          "currency_code" => "ZAR",
          "account_id" => "01958e51-7c5a-7000-8000-000000000013",
          "payee" => "ext:01958e51-7c5a-7000-8000-000000000014",
          "beneficiary_id" => "01958e51-7c5a-7000-8000-000000000015",
          "external_account_id" => "01958e51-7c5a-7000-8000-000000000014",
          "destination_account_id" => nil,
          "payment_reference" => "INV-2026-001",
          "client_reference" => "po_8812"
        },
        "signature_input" => "manza.transfer-authorization.v1|01958e51-7c5a-7000-8000-000000000012|" \
                             "9f86d081884c7d659a2feaa0c55ad015|2500.0|ZAR|01958e51-7c5a-7000-8000-000000000013|" \
                             "ext:01958e51-7c5a-7000-8000-000000000014|po_8812"
      }
    }
  end
  let(:ledger_entry) do
    {
      payment_id: "01958e51-7c5a-7000-8000-000000000012",
      amount: "2500.0",
      currency_code: "ZAR",
      account_id: "01958e51-7c5a-7000-8000-000000000013",
      payee: "ext:01958e51-7c5a-7000-8000-000000000014"
    }
  end
  let(:dir) { Dir.mktmpdir }
  let(:ledger) { TransferAuthorizer::Ledger.new(File.join(dir, "ledger.json")) }
  let(:log) { StringIO.new }
  let(:app) do
    described_class.new(
      client: Manza::Client.new(api_key: "key-b", base_url: base_url),
      secret: secret,
      ledger: ledger,
      executor: ->(&job) { job.call },
      logger: Logger.new(log),
      ledger_wait: 0
    )
  end

  after { FileUtils.remove_entry(dir) }

  def deliver(body, signature: nil, timestamp: Time.now.to_i.to_s)
    signature ||= Manza::Webhook.sign(payload: body, timestamp: timestamp, secret: secret)
    Rack::MockRequest.new(app).post(
      "/", input: body, "CONTENT_TYPE" => "application/json",
           "HTTP_X_MANZA_SIGNATURE" => signature, "HTTP_X_MANZA_TIMESTAMP" => timestamp
    )
  end

  def expected_signature
    input = Manza::TransferAuthorization.signature_input(
      **ledger_entry, nonce: "9f86d081884c7d659a2feaa0c55ad015", client_reference: "po_8812"
    )
    Manza::TransferAuthorization.sign(secret: secret, signature_input: input)
  end

  describe "with a matching ledger entry" do
    before { ledger.record("po_8812", **ledger_entry) }

    it "signs from the ledger and authorizes with key B" do
      stub = stub_request(:post, "#{base_url}/api/transfer_drafts/#{draft_id}/authorize")
             .with(
               headers: { "Authorization" => "Bearer key-b" },
               body: { "authorization_id" => authorization_id, "signature" => expected_signature }
             )
             .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                        body: JSON.generate("id" => draft_id, "status" => "processing"))

      response = deliver(JSON.generate(example_payload))

      expect(response.status).to eq(200)
      expect(stub).to have_been_requested.once
      expect(log.string).to include("verified", "ledger match", "signed", "authorized")
    end

    it "logs the API error type and request id when authorize fails" do
      stub_request(:post, "#{base_url}/api/transfer_drafts/#{draft_id}/authorize")
        .to_return(status: 422, headers: { "Content-Type" => "application/json", "X-Request-Id" => "req_123" },
                   body: JSON.generate("error" => { "message" => "Signature does not match", "type" => "invalid_signature" }))

      response = deliver(JSON.generate(example_payload))

      expect(response.status).to eq(200)
      expect(log.string).to include("invalid_signature", "req_123")
    end

    it "logs both signature inputs when the webhook's differs from the ledger's" do
      stub = stub_request(:post, "#{base_url}/api/transfer_drafts/#{draft_id}/authorize")
             .with(body: hash_including("signature" => expected_signature))
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")
      payload = JSON.parse(JSON.generate(example_payload))
      payload["data"]["signature_input"] = "something-else"

      deliver(JSON.generate(payload))

      expect(stub).to have_been_requested.once
      expect(log.string).to include("something-else", example_payload["data"]["signature_input"])
    end
  end

  describe "with a ledger mismatch" do
    before { ledger.record("po_8812", **ledger_entry, amount: "25000.0") }

    it "declines with a reason naming the field" do
      stub = stub_request(:post, "#{base_url}/api/transfer_drafts/#{draft_id}/decline")
             .with(body: hash_including("authorization_id" => authorization_id, "reason" => /amount/))
             .to_return(status: 200, headers: { "Content-Type" => "application/json" },
                        body: JSON.generate("id" => authorization_id, "status" => "declined"))

      response = deliver(JSON.generate(example_payload))

      expect(response.status).to eq(200)
      expect(stub).to have_been_requested.once
      expect(a_request(:post, %r{/authorize\z})).not_to have_been_made
      expect(log.string).to include("declined")
    end
  end

  describe "without a ledger entry" do
    it "declines a client_reference this authorizer never issued" do
      stub = stub_request(:post, "#{base_url}/api/transfer_drafts/#{draft_id}/decline")
             .with(body: hash_including("reason" => /po_8812/))
             .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: "{}")

      deliver(JSON.generate(example_payload))

      expect(stub).to have_been_requested.once
    end
  end

  describe "with a bad signature" do
    it "answers 401 and calls nothing" do
      response = deliver(JSON.generate(example_payload), signature: "0" * 64)

      expect(response.status).to eq(401)
      expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
    end
  end

  describe "with a signed body that is not a JSON object" do
    it "answers 401 and calls nothing" do
      response = deliver("[]")

      expect(response.status).to eq(401)
      expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
    end
  end

  describe "with another event" do
    it "answers 200 and calls nothing" do
      response = deliver(JSON.generate("event" => "test.ping", "event_id" => "0199a1b2-0000-7000-8000-000000000010"))

      expect(response.status).to eq(200)
      expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
    end
  end
end
