# frozen_string_literal: true

require "spec_helper"

RSpec.describe Zazu::Resources::PayeeTrustRequests do
  let(:client) { zazu_client }

  describe "#create", vcr: { cassette_name: "payee_trust_requests/create" } do
    it "files a pending trust request" do
      response = client.payee_trust_requests.create(
        external_account_ids: [fixture_id("ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID")]
      )

      expect(response.status).to eq(201)
      expect(response.body["status"]).to eq("pending")
      expect(response.body["external_account_ids"]).to eq([fixture_id("ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID")])
    end
  end

  describe "#get", vcr: { cassette_name: "payee_trust_requests/get" } do
    it "returns a single trust request" do
      response = client.payee_trust_requests.get(fixture_id("ZAZU_FIXTURE_PAYEE_TRUST_REQUEST_ID"))

      expect(response.body["id"]).to eq(fixture_id("ZAZU_FIXTURE_PAYEE_TRUST_REQUEST_ID"))
      expect(response.body["resolved_at"]).to be_nil
    end
  end
end
