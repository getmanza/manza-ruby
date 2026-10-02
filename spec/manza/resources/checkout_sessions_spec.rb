# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::CheckoutSessions do
  let(:client) { manza_client }

  describe "#create", vcr: { cassette_name: "checkout_sessions/create" } do
    it "creates a checkout session" do
      response = client.checkout_sessions.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        amount: "100.00",
        success_url: "https://example.com/zazu-fixture-success?session_id={CHECKOUT_SESSION_ID}",
        cancel_url: "https://example.com/zazu-fixture-cancel",
        description: "Created by zazu-ruby fixture spec",
        customer_email: "fixture@example.com",
        metadata: { order_id: "ORD-FIXTURE" }
      )
      expect(response.status).to eq(201)
      expect(response.body["id"]).to be_a(String)
      expect(response.body["url"]).to be_a(String)
      expect(response.body["status"]).to eq("open")
    end
  end

  describe "#get", vcr: { cassette_name: "checkout_sessions/get" } do
    it "returns a single checkout session" do
      response = client.checkout_sessions.get(fixture_id("MANZA_FIXTURE_CHECKOUT_SESSION_ID"))
      expect(response.body["id"]).to be_a(String)
      expect(response.body["status"]).to be_a(String)
    end
  end
end
