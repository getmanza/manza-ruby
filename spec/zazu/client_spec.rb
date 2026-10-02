# frozen_string_literal: true

require "spec_helper"

RSpec.describe Zazu::Client do
  describe ".new" do
    it "raises ConfigurationError when api_key is missing" do
      expect { described_class.new(api_key: nil) }
        .to raise_error(Zazu::ConfigurationError, /Missing api_key/)
    end

    it "raises ConfigurationError when api_key is empty" do
      expect { described_class.new(api_key: "") }
        .to raise_error(Zazu::ConfigurationError, /Missing api_key/)
    end

    it "strips trailing slash from base_url" do
      client = described_class.new(api_key: "k", base_url: "https://api.zazu.ma/")
      expect(client.base_url).to eq("https://api.zazu.ma")
    end

    it "defaults base_url to https://zazu.ma" do
      client = described_class.new(api_key: "k")
      expect(client.base_url).to eq("https://zazu.ma")
    end

    it "reads api_key from ZAZU_API_KEY env var" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ZAZU_API_KEY", nil).and_return("env-key")
      allow(ENV).to receive(:fetch).with("ZAZU_BASE_URL", anything).and_return("https://zazu.ma")
      allow(ENV).to receive(:fetch).with("ZAZU_API_VERSION", nil).and_return(nil)
      allow(ENV).to receive(:fetch).with("ZAZU_TIMEOUT", anything).and_return("30")
      client = described_class.new
      expect(client.api_key).to eq("env-key")
    end
  end

  describe "resource accessors" do
    let(:client) { described_class.new(api_key: "k") }

    it "memoizes accounts so the same instance is returned" do
      first = client.accounts
      second = client.accounts
      expect(first).to be(second)
    end

    it "exposes every resource module" do
      modules = {
        accounts: Zazu::Resources::Accounts,
        customers: Zazu::Resources::Customers,
        entity: Zazu::Resources::Entity,
        invoices: Zazu::Resources::Invoices,
        payment_links: Zazu::Resources::PaymentLinks,
        payee_trust_requests: Zazu::Resources::PayeeTrustRequests,
        webhook_endpoints: Zazu::Resources::WebhookEndpoints
      }
      modules.each do |accessor, klass|
        expect(client.public_send(accessor)).to be_a(klass)
      end
    end
  end

  describe "error mapping" do
    let(:client) { described_class.new(api_key: "k", base_url: "https://staging.zazu.example") }

    def stub_error(status, error)
      stub_request(:get, "https://staging.zazu.example/api/entity")
        .to_return(status: status, body: { error: error }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "maps 400 to ValidationError" do
      stub_error(400, { message: "limit is malformed", type: "invalid_request_error" })

      expect { client.entity.get }.to raise_error(Zazu::ValidationError) { |e|
        expect(e.status).to eq(400)
        expect(e.message).to eq("limit is malformed")
        expect(e.type).to eq("invalid_request_error")
      }
    end

    it "maps 409 to ConflictError carrying error.payment_id" do
      stub_error(409, { message: "A transfer with this client_reference already exists",
                        type: "duplicate_client_reference", param: "client_reference", payment_id: "pay_1" })

      expect { client.entity.get }.to raise_error(Zazu::ConflictError) { |e|
        expect(e.status).to eq(409)
        expect(e.type).to eq("duplicate_client_reference")
        expect(e.param).to eq("client_reference")
        expect(e.payment_id).to eq("pay_1")
      }
    end

    it "leaves payment_id nil when a 409 omits it" do
      stub_error(409, { message: "Conflict" })

      expect { client.entity.get }.to raise_error(Zazu::ConflictError) { |e| expect(e.payment_id).to be_nil }
    end

    it "includes payment_id in ConflictError#to_h" do
      error = Zazu::ConflictError.new("dup", status: 409, payment_id: "pay_1")

      expect(error.to_h).to include(error: "ConflictError", payment_id: "pay_1")
    end
  end
end
