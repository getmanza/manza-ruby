# frozen_string_literal: true

require "spec_helper"

# Fixed test vector, shared by every SDK in the family. Each SDK's
# verifier must accept exactly this delivery. The signature was
# computed independently with:
#
#   printf '%s' '1767225600.<payload>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
#
#   secret    whsec_test_vector_secret
#   timestamp 1767225600
#   payload   {"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"}
#   signature 970fdd13680015f73dbd172884498c6fd1e07d5b5c41aae081272598607fea75
RSpec.describe Manza::Webhook do
  let(:secret) { "whsec_test_vector_secret" }
  let(:timestamp) { "1767225600" }
  let(:payload) { '{"event":"test.ping","event_id":"0199a1b2-0000-7000-8000-000000000010"}' }
  let(:signature) { "970fdd13680015f73dbd172884498c6fd1e07d5b5c41aae081272598607fea75" }
  let(:now) { Time.at(1_767_225_600) }

  describe ".sign" do
    it "signs the shared vector" do
      expect(described_class.sign(payload: payload, timestamp: timestamp, secret: secret)).to eq(signature)
    end

    it "accepts an Integer timestamp" do
      expect(described_class.sign(payload: payload, timestamp: 1_767_225_600, secret: secret)).to eq(signature)
    end
  end

  describe ".verify?" do
    def verify(**overrides)
      described_class.verify?(payload: payload, signature: signature, timestamp: timestamp, secret: secret, now: now, **overrides)
    end

    it "accepts the shared vector" do
      expect(verify).to be(true)
    end

    it "rejects a wrong secret" do
      expect(verify(secret: "whsec_other")).to be(false)
    end

    it "rejects a tampered payload" do
      expect(verify(payload: payload.sub("ping", "pong"))).to be(false)
    end

    it "rejects a signature of the wrong length without raising" do
      expect(verify(signature: "abc")).to be(false)
    end

    it "rejects a timestamp 301 seconds old" do
      expect(verify(now: now + 301)).to be(false)
    end

    it "rejects a timestamp 301 seconds in the future" do
      expect(verify(now: now - 301)).to be(false)
    end

    it "accepts a timestamp exactly at the tolerance" do
      expect(verify(now: now + 300)).to be(true)
    end

    it "skips the timestamp check with tolerance: nil" do
      expect(verify(now: now + 86_400, tolerance: nil)).to be(true)
    end

    it "rejects a non-numeric timestamp" do
      expect(verify(timestamp: "yesterday", tolerance: nil)).to be(false)
    end

    it "rejects nil inputs" do
      expect(verify(signature: nil)).to be(false)
      expect(verify(timestamp: nil)).to be(false)
      expect(verify(payload: nil)).to be(false)
      expect(verify(secret: nil)).to be(false)
    end
  end

  describe ".construct_event" do
    def construct(headers, **overrides)
      described_class.construct_event(payload: payload, headers: headers, secret: secret, now: now, **overrides)
    end

    it "returns the parsed event for X-Manza-* headers" do
      event = construct({ "X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp })

      expect(event).to eq("event" => "test.ping", "event_id" => "0199a1b2-0000-7000-8000-000000000010")
    end

    it "reads mixed-case header names" do
      expect(construct({ "x-MANZA-signature" => signature, "X-manza-Timestamp" => timestamp })["event"]).to eq("test.ping")
    end

    it "reads the Rack env form" do
      expect(construct({ "HTTP_X_MANZA_SIGNATURE" => signature, "HTTP_X_MANZA_TIMESTAMP" => timestamp })["event"]).to eq("test.ping")
    end

    it "falls back to X-Zazu-* headers" do
      expect(construct({ "X-Zazu-Signature" => signature, "X-Zazu-Timestamp" => timestamp })["event"]).to eq("test.ping")
    end

    it "prefers X-Manza-* over X-Zazu-*" do
      headers = { "X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp,
                  "X-Zazu-Signature" => "0" * 64, "X-Zazu-Timestamp" => "1" }

      expect(construct(headers)["event"]).to eq("test.ping")
    end

    it "raises on a missing signature header" do
      expect { construct({ "X-Manza-Timestamp" => timestamp }) }
        .to raise_error(Manza::ArgumentError, "missing X-Manza-Signature header")
    end

    it "raises on a missing timestamp header" do
      expect { construct({ "X-Manza-Signature" => signature }) }
        .to raise_error(Manza::ArgumentError, "missing X-Manza-Timestamp header")
    end

    it "raises on a bad signature" do
      expect { construct({ "X-Manza-Signature" => "0" * 64, "X-Manza-Timestamp" => timestamp }) }
        .to raise_error(Manza::ArgumentError, "invalid webhook signature")
    end

    it "raises on a stale timestamp" do
      expect { construct({ "X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp }, now: now + 301) }
        .to raise_error(Manza::ArgumentError, "webhook timestamp outside tolerance")
    end

    it "accepts a stale timestamp with tolerance: nil" do
      event = construct({ "X-Manza-Signature" => signature, "X-Manza-Timestamp" => timestamp }, now: now + 301, tolerance: nil)

      expect(event["event"]).to eq("test.ping")
    end

    it "raises on a body that is not JSON" do
      body = "not json"
      headers = { "X-Manza-Signature" => described_class.sign(payload: body, timestamp: timestamp, secret: secret),
                  "X-Manza-Timestamp" => timestamp }

      expect { construct(headers, payload: body) }.to raise_error(Manza::ArgumentError, "webhook payload is not JSON")
    end
  end
end
