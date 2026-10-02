# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Client do
  describe ".new" do
    it "raises ConfigurationError when api_key is missing" do
      expect { described_class.new(api_key: nil) }
        .to raise_error(Manza::ConfigurationError, /Missing api_key/)
    end

    it "raises ConfigurationError when api_key is empty" do
      expect { described_class.new(api_key: "") }
        .to raise_error(Manza::ConfigurationError, /Missing api_key/)
    end

    it "strips trailing slash from base_url" do
      client = described_class.new(api_key: "k", base_url: "https://api.manza.example/")
      expect(client.base_url).to eq("https://api.manza.example")
    end
  end

  describe "environment configuration" do
    let(:env_names) { %w[API_KEY BASE_URL API_VERSION TIMEOUT].flat_map { |n| ["MANZA_#{n}", "ZAZU_#{n}"] } }

    around do |example|
      saved = env_names.to_h { |name| [name, ENV.fetch(name, nil)] }
      env_names.each { |name| ENV.delete(name) }
      described_class.instance_variable_set(:@warned_legacy_env, nil)
      example.run
    ensure
      saved.each { |name, value| value.nil? ? ENV.delete(name) : ENV[name] = value }
      described_class.instance_variable_set(:@warned_legacy_env, nil)
    end

    {
      "API_KEY" => [:api_key, "env-key", "env-key"],
      "BASE_URL" => [:base_url, "https://env.example", "https://env.example"],
      "API_VERSION" => [:api_version, "2026-10-01", "2026-10-01"],
      "TIMEOUT" => [:timeout, "12", 12]
    }.each do |suffix, (attribute, raw, expected)|
      it "reads #{attribute} from MANZA_#{suffix}" do
        ENV["MANZA_API_KEY"] ||= "k"
        ENV["MANZA_#{suffix}"] = raw

        expect { expect(described_class.new.public_send(attribute)).to eq(expected) }
          .not_to output.to_stderr
      end

      it "falls back to ZAZU_#{suffix} with a deprecation warning" do
        ENV["MANZA_API_KEY"] = "k" unless suffix == "API_KEY"
        ENV["ZAZU_#{suffix}"] = raw

        expect { expect(described_class.new.public_send(attribute)).to eq(expected) }
          .to output(/ZAZU_#{suffix} is deprecated.*MANZA_#{suffix}/).to_stderr
      end

      it "prefers MANZA_#{suffix} over ZAZU_#{suffix}" do
        ENV["MANZA_API_KEY"] ||= "k"
        ENV["MANZA_#{suffix}"] = raw
        ENV["ZAZU_#{suffix}"] = "99"

        expect { expect(described_class.new.public_send(attribute)).to eq(expected) }
          .not_to output.to_stderr
      end
    end

    it "warns about each legacy variable only once per process" do
      ENV["ZAZU_API_KEY"] = "k"

      expect { described_class.new }.to output(/ZAZU_API_KEY/).to_stderr
      expect { described_class.new }.not_to output.to_stderr
    end

    it "does not warn when the value is passed explicitly" do
      ENV["ZAZU_API_KEY"] = "legacy"

      expect { described_class.new(api_key: "k") }.not_to output.to_stderr
    end

    it "defaults base_url to https://ma.manza.finance" do
      expect(described_class.new(api_key: "k").base_url).to eq("https://ma.manza.finance")
    end

    it "names MANZA_API_KEY when no key is configured" do
      expect { described_class.new }
        .to raise_error(Manza::ConfigurationError, /MANZA_API_KEY/)
    end
  end

  describe "request headers" do
    it "sends the manza-ruby User-Agent and the Manza-Version header" do
      stub = stub_request(:get, "https://staging.manza.example/api/entity")
             .with(headers: { "User-Agent" => "manza-ruby/#{Manza::VERSION}", "Manza-Version" => "2026-10-01" })
             .to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })

      described_class.new(api_key: "k", base_url: "https://staging.manza.example", api_version: "2026-10-01").entity.get

      expect(stub).to have_been_requested
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
        accounts: Manza::Resources::Accounts,
        customers: Manza::Resources::Customers,
        entity: Manza::Resources::Entity,
        invoices: Manza::Resources::Invoices,
        payment_links: Manza::Resources::PaymentLinks,
        payee_trust_requests: Manza::Resources::PayeeTrustRequests,
        webhook_endpoints: Manza::Resources::WebhookEndpoints
      }
      modules.each do |accessor, klass|
        expect(client.public_send(accessor)).to be_a(klass)
      end
    end
  end

  describe "error mapping" do
    let(:client) { described_class.new(api_key: "k", base_url: "https://staging.manza.example") }

    def stub_error(status, error)
      stub_request(:get, "https://staging.manza.example/api/entity")
        .to_return(status: status, body: { error: error }.to_json,
                   headers: { "Content-Type" => "application/json" })
    end

    it "maps 400 to ValidationError" do
      stub_error(400, { message: "limit is malformed", type: "invalid_request_error" })

      expect { client.entity.get }.to raise_error(Manza::ValidationError) { |e|
        expect(e.status).to eq(400)
        expect(e.message).to eq("limit is malformed")
        expect(e.type).to eq("invalid_request_error")
      }
    end

    it "maps 409 to ConflictError carrying error.payment_id" do
      stub_error(409, { message: "A transfer with this client_reference already exists",
                        type: "duplicate_client_reference", param: "client_reference", payment_id: "pay_1" })

      expect { client.entity.get }.to raise_error(Manza::ConflictError) { |e|
        expect(e.status).to eq(409)
        expect(e.type).to eq("duplicate_client_reference")
        expect(e.param).to eq("client_reference")
        expect(e.payment_id).to eq("pay_1")
      }
    end

    it "leaves payment_id nil when a 409 omits it" do
      stub_error(409, { message: "Conflict" })

      expect { client.entity.get }.to raise_error(Manza::ConflictError) { |e| expect(e.payment_id).to be_nil }
    end

    it "includes payment_id in ConflictError#to_h" do
      error = Manza::ConflictError.new("dup", status: 409, payment_id: "pay_1")

      expect(error.to_h).to include(error: "ConflictError", payment_id: "pay_1")
    end
  end
end
