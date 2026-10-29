# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::TransferAuthorizer do
  describe "#get", vcr: { cassette_name: "transfer_authorizer/get" } do
    it "returns the enrolled authorizer's status, limits and usage" do
      response = manza_authorizer_client.transfer_authorizer.get

      expect(response.status).to eq(200)
      expect(response.body["status"]).to eq("active")
      expect(response.body["suspension_reason"]).to be_nil
      expect(response.body["currency_code"]).to eq("MAD")
      expect(response.body).to include("per_transfer_limit", "daily_limit", "daily_authorized_total",
                                       "secret_expires_at", "webhook_endpoint_id", "enrolled_at")
    end
  end
end
