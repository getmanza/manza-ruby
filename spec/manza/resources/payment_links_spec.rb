# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::PaymentLinks do
  let(:client) { manza_client }

  describe "#list", vcr: { cassette_name: "payment_links/list" } do
    it "returns a Page" do
      page = client.payment_links.list
      expect(page).to be_a(Manza::Page)
    end
  end

  describe "#get", vcr: { cassette_name: "payment_links/get" } do
    it "returns a single payment link" do
      response = client.payment_links.get(fixture_id("MANZA_FIXTURE_PAYMENT_LINK_ID"))
      expect(response.body["id"]).to be_a(String)
    end
  end

  describe "#create", vcr: { cassette_name: "payment_links/create" } do
    it "creates a payment link" do
      response = client.payment_links.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        amount: "100.00",
        title: "SDK fixture",
        description: "Created by zazu-ruby fixture spec",
        link_type: "single"
      )
      expect(response.status).to eq(201)
    end
  end

  describe "#cancel", vcr: { cassette_name: "payment_links/cancel" } do
    it "cancels a payment link" do
      response = client.payment_links.cancel(
        fixture_id("MANZA_FIXTURE_CANCELLABLE_PAYMENT_LINK_ID")
      )
      expect(response.success?).to be true
    end
  end
end
