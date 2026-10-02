# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::WebhookEndpoints do
  let(:client) { manza_client }

  describe "#list", vcr: { cassette_name: "webhook_endpoints/list" } do
    it "returns a Page" do
      page = client.webhook_endpoints.list
      expect(page).to be_a(Manza::Page)
    end
  end

  describe "#get", vcr: { cassette_name: "webhook_endpoints/get" } do
    it "returns a single webhook endpoint" do
      response = client.webhook_endpoints.get(
        fixture_id("MANZA_FIXTURE_WEBHOOK_ID")
      )
      expect(response.body["id"]).to be_a(String)
    end
  end

  describe "#create", vcr: { cassette_name: "webhook_endpoints/create" } do
    it "creates a webhook endpoint" do
      response = client.webhook_endpoints.create(
        url: "https://example.com/zazu-webhooks",
        events: ["payment_link.paid"],
        description: "SDK fixture endpoint"
      )
      expect(response.status).to eq(201)
    end
  end

  describe "#update", vcr: { cassette_name: "webhook_endpoints/update" } do
    it "updates a webhook endpoint" do
      response = client.webhook_endpoints.update(
        fixture_id("MANZA_FIXTURE_WEBHOOK_ID"),
        description: "Updated description",
        events: ["payment_link.paid"]
      )
      expect(response.success?).to be true
    end
  end

  describe "#delete", vcr: { cassette_name: "webhook_endpoints/delete" } do
    it "deletes a webhook endpoint" do
      response = client.webhook_endpoints.delete(
        fixture_id("MANZA_FIXTURE_DELETABLE_WEBHOOK_ID")
      )
      expect(response.status).to eq(204)
    end
  end

  describe "#test_endpoint", vcr: { cassette_name: "webhook_endpoints/test" } do
    it "fires a test event" do
      response = client.webhook_endpoints.test_endpoint(
        fixture_id("MANZA_FIXTURE_WEBHOOK_ID")
      )
      expect(response.success?).to be true
    end
  end

  describe "#regenerate_secret", vcr: { cassette_name: "webhook_endpoints/regenerate_secret" } do
    it "rotates the webhook secret" do
      response = client.webhook_endpoints.regenerate_secret(
        fixture_id("MANZA_FIXTURE_WEBHOOK_ID")
      )
      expect(response.success?).to be true
    end
  end

  describe "#enable", vcr: { cassette_name: "webhook_endpoints/enable" } do
    it "enables an endpoint" do
      response = client.webhook_endpoints.enable(
        fixture_id("MANZA_FIXTURE_DISABLED_WEBHOOK_ID")
      )
      expect(response.success?).to be true
    end
  end

  describe "#disable", vcr: { cassette_name: "webhook_endpoints/disable" } do
    it "disables an endpoint" do
      response = client.webhook_endpoints.disable(
        fixture_id("MANZA_FIXTURE_ENABLED_WEBHOOK_ID")
      )
      expect(response.success?).to be true
    end
  end
end
