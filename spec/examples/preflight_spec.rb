# frozen_string_literal: true

require "spec_helper"
require "stringio"
require_relative "../../examples/transfer_authorizer/preflight"

# Drives the example's preflight against WebMock stubs of the documented
# responses. No cassette, no network: each failure is a stubbed response.
RSpec.describe TransferAuthorizer::Preflight do
  let(:base_url) { "https://staging.manza.example" }
  let(:account_id) { "01958e51-7c5a-7000-8000-000000000013" }
  let(:beneficiary_id) { "01958e51-7c5a-7000-8000-000000000015" }
  let(:endpoint_id) { "01958e51-7c5a-7000-8000-000000000020" }
  let(:now) { Time.utc(2026, 10, 20, 12) }
  let(:env) do
    {
      "MANZA_BASE_URL" => base_url,
      "MANZA_CREATOR_API_KEY" => "key-a",
      "MANZA_AUTHORIZER_API_KEY" => "key-b",
      "MANZA_AUTHORIZER_SECRET" => "whsec_example",
      "MANZA_ACCOUNT_ID" => account_id,
      "MANZA_BENEFICIARY_ID" => beneficiary_id
    }
  end
  let(:authorizer) do
    {
      "status" => "active", "suspension_reason" => nil, "currency_code" => "MAD", "per_transfer_limit" => "1000.0",
      "daily_limit" => "5000.0", "daily_authorized_total" => "100.0", "secret_expires_at" => "2027-01-18T00:00:00Z",
      "webhook_endpoint_id" => endpoint_id, "enrolled_at" => "2026-10-01T08:30:00Z"
    }
  end
  let(:endpoint) { { "id" => endpoint_id, "url" => "https://authorizer.example.com/", "status" => "active" } }
  let(:payee) { { "id" => "01958e51-7c5a-7000-8000-000000000014", "default" => true, "trusted" => true } }

  def json(status, body, headers = {})
    { status: status, headers: { "Content-Type" => "application/json" }.merge(headers), body: JSON.generate(body) }
  end

  def error(status, type, message = "refused")
    json(status, { "error" => { "type" => type, "message" => message } })
  end

  before do
    stub_request(:get, "#{base_url}/api/entity").with(headers: { "Authorization" => "Bearer key-a" })
                                                .to_return(json(200, { "id" => "e1", "name" => "Acme" }))
    stub_request(:get, "#{base_url}/api/transfer_authorizer").with(headers: { "Authorization" => "Bearer key-b" })
                                                             .to_return { json(200, authorizer) }
    key_a = { "Authorization" => "Bearer key-a" }
    beneficiary = { "id" => beneficiary_id, "external_accounts" => [payee] }
    stub_request(:get, "#{base_url}/api/accounts/#{account_id}")
      .with(headers: key_a).to_return(json(200, { "id" => account_id, "currency_code" => "MAD" }))
    stub_request(:get, "#{base_url}/api/webhook_endpoints/#{endpoint_id}").with(headers: key_a).to_return { json(200, endpoint) }
    stub_request(:get, "#{base_url}/api/beneficiaries/#{beneficiary_id}").with(headers: key_a).to_return { json(200, beneficiary) }
  end

  def run(amount: "10.00")
    out = StringIO.new
    ok = described_class.new(env: env, amount: amount, out: out, now: now).run
    [ok, out.string]
  end

  def failures(output)
    output.lines.grep(/\A✗/)
  end

  it "passes every step when the setup is complete" do
    ok, output = run

    expect(ok).to be(true)
    expect(failures(output)).to be_empty
    expect(output.lines.grep(/\A✓/).size).to eq(9)
  end

  it "fails when a key is missing" do
    env["MANZA_AUTHORIZER_API_KEY"] = ""
    ok, output = run

    expect(ok).to be(false)
    expect(failures(output).first).to include("MANZA_AUTHORIZER_API_KEY")
    expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
  end

  it "fails when the account or beneficiary id is missing" do
    env["MANZA_BENEFICIARY_ID"] = ""
    ok, output = run

    expect(ok).to be(false)
    expect(failures(output).first).to include("MANZA_BENEFICIARY_ID")
    expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
  end

  it "fails when the amount is not a decimal, and runs the other checks" do
    ok, output = run(amount: "ten")

    expect(ok).to be(false)
    expect(failures(output)).to contain_exactly(a_string_including("\"ten\"", "10.00"))
    expect(output).to include("✓ transfer authorizer is active")
    expect(output).not_to include("limit per transfer and")
  end

  it "fails when the amount is not positive" do
    %w[-5 0 1/2 1e2].each do |amount|
      _, output = run(amount: amount)

      expect(failures(output).first).to include(amount.inspect, "positive")
    end
  end

  it "stops before any request on a missing key, even with a bad amount" do
    env["MANZA_CREATOR_API_KEY"] = ""
    _, output = run(amount: "0")

    expect(failures(output).size).to eq(2)
    expect(a_request(:any, /staging\.manza\.example/)).not_to have_been_made
  end

  it "fails when both keys are the same" do
    env["MANZA_AUTHORIZER_API_KEY"] = "key-a"
    _, output = run

    expect(failures(output).first).to include("different")
  end

  it "fails when key A cannot reach the entity" do
    stub_request(:get, "#{base_url}/api/entity").to_return(error(401, "authentication_error"))
    _, output = run

    expect(failures(output).first).to include("key A", "MANZA_CREATOR_API_KEY")
  end

  it "fails when no authorizer is enrolled" do
    stub_request(:get, "#{base_url}/api/transfer_authorizer").to_return(error(404, "not_found_error"))
    _, output = run

    expect(failures(output).first).to include("no transfer authorizer is enrolled", "Transfer approval")
  end

  it "fails when key B cannot read the authorizer" do
    stub_request(:get, "#{base_url}/api/transfer_authorizer").to_return(error(403, "insufficient_scope"))
    _, output = run

    expect(failures(output).first).to include("key B", "insufficient_scope", "transfers:authorize")
  end

  it "fails when key A cannot read the account" do
    stub_request(:get, "#{base_url}/api/accounts/#{account_id}").to_return(error(403, "insufficient_scope"))
    _, output = run

    expect(failures(output).first).to include("key A", "accounts:read")
  end

  it "fails when key A cannot read the enrolled webhook endpoint" do
    stub_request(:get, "#{base_url}/api/webhook_endpoints/#{endpoint_id}").to_return(error(403, "insufficient_scope"))
    _, output = run

    expect(failures(output).first).to include("key A", "webhook_endpoints:read")
  end

  it "fails when key A cannot read the beneficiary" do
    stub_request(:get, "#{base_url}/api/beneficiaries/#{beneficiary_id}").to_return(error(404, "not_found_error"))
    _, output = run

    expect(failures(output).first).to include("key A", "MANZA_BENEFICIARY_ID")
  end

  it "fails once, on the authorizer line, when the secret has expired" do
    authorizer.merge!("status" => "suspended", "suspension_reason" => "secret_expired", "secret_expires_at" => "2026-10-19T00:00:00Z")
    _, output = run

    expect(failures(output)).to contain_exactly(a_string_including("suspended (secret_expired)", "rotates the secret"))
  end

  it "fails when the enrolled webhook endpoint was deleted" do
    stub_request(:get, "#{base_url}/api/webhook_endpoints/#{endpoint_id}").to_return(error(404, "not_found_error"))
    _, output = run

    expect(failures(output).first).to include("was deleted", "enrol")
  end

  it "fails with the suspension reason and its fix" do
    authorizer.merge!("status" => "suspended", "suspension_reason" => "endpoint_disabled")
    _, output = run

    expect(failures(output).first).to include("suspended (endpoint_disabled)", "re-enable")
  end

  it "fails when the account's currency is not the enrolled one" do
    stub_request(:get, "#{base_url}/api/accounts/#{account_id}").to_return(json(200, { "id" => account_id, "currency_code" => "ZAR" }))
    _, output = run

    expect(failures(output).first).to include("ZAR", "MAD")
  end

  it "fails when the secret expires within 7 days" do
    authorizer["secret_expires_at"] = "2026-10-23T00:00:00Z"
    _, output = run

    expect(failures(output).first).to include("secret expires", "rotate")
  end

  it "fails when the signing secret is not set" do
    env["MANZA_AUTHORIZER_SECRET"] = ""
    _, output = run

    expect(failures(output).first).to include("MANZA_AUTHORIZER_SECRET")
  end

  it "fails when the enrolled webhook endpoint is disabled" do
    endpoint["status"] = "disabled"
    _, output = run

    expect(failures(output).first).to include("disabled", "enable", "if the authorizer stays suspended")
  end

  it "warns when the endpoint is on a URL that changes when the tunnel restarts" do
    endpoint["url"] = "https://abc123.ngrok-free.app/"
    ok, output = run

    expect(ok).to be(true)
    expect(output.lines.grep(/\A!/).first).to include("ngrok-free.app", "reserved domain")
  end

  it "fails when the amount is over the limit per transfer" do
    _, output = run(amount: "1500.00")

    expect(failures(output).first).to include("limit per transfer")
  end

  it "fails when the amount does not fit in the last 24 hours' room" do
    authorizer["daily_authorized_total"] = "4995.0"
    _, output = run

    expect(failures(output).first).to include("24 hours")
  end

  it "warns that a new payee needs the toggle, which the API does not show" do
    payee["trusted"] = false
    ok, output = run

    expect(ok).to be(true)
    expect(output.lines.grep(/\A!/).first).to include("not trusted yet", "Approve transfers to new payees", "IP allowlist")
  end

  it "fails when the beneficiary has no default bank account" do
    payee["default"] = false
    _, output = run

    expect(failures(output).first).to include("default bank account")
  end
end
