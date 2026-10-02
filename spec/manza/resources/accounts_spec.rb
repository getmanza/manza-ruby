# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::Accounts do
  let(:client) { manza_client }

  describe "#list", vcr: { cassette_name: "accounts/list" } do
    it "returns a Page of accounts" do
      page = client.accounts.list
      expect(page).to be_a(Manza::Page)
      expect(page.data).to be_an(Array)
    end
  end

  describe "#list with currency_code filter", vcr: { cassette_name: "accounts/list_currency_filtered" } do
    it "passes the filter through" do
      page = client.accounts.list(currency_code: "MAD")
      expect(page).to be_a(Manza::Page)
    end
  end

  describe "#list with invalid limit" do
    it "raises before making a request when limit > 100" do
      expect { client.accounts.list(limit: 500) }
        .to raise_error(Manza::ArgumentError, /cannot exceed 100/)
    end
  end

  describe "#get", vcr: { cassette_name: "accounts/get" } do
    it "returns a single account" do
      response = client.accounts.get(fixture_id("MANZA_FIXTURE_ACCOUNT_ID"))
      expect(response).to be_a(Manza::Response)
      expect(response.body["id"]).to be_a(String)
    end
  end

  describe "#list_transactions", vcr: { cassette_name: "accounts/list_transactions" } do
    it "returns a Page of transactions" do
      account_id = fixture_id("MANZA_FIXTURE_ACCOUNT_ID")
      page = client.accounts.list_transactions(account_id)
      expect(page).to be_a(Manza::Page)
      expect(page.data).to be_an(Array)
    end
  end

  describe "#get_transaction", vcr: { cassette_name: "accounts/get_transaction" } do
    it "returns a single transaction" do
      account_id = fixture_id("MANZA_FIXTURE_ACCOUNT_ID")
      transaction_id = fixture_id("MANZA_FIXTURE_TRANSACTION_ID")
      response = client.accounts.get_transaction(account_id, transaction_id)
      expect(response.body["id"]).to be_a(String)
    end
  end
end
