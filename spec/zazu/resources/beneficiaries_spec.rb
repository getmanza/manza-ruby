# frozen_string_literal: true

require "spec_helper"

RSpec.describe Zazu::Resources::Beneficiaries do
  let(:client) { zazu_client }

  describe "#list", vcr: { cassette_name: "beneficiaries/list" } do
    it "returns a Page of beneficiaries with their bank accounts" do
      page = client.beneficiaries.list

      expect(page).to be_a(Zazu::Page)
      expect(page.data.first["external_accounts"]).to be_an(Array)
    end
  end

  describe "#get", vcr: { cassette_name: "beneficiaries/get" } do
    it "returns a single beneficiary" do
      response = client.beneficiaries.get(fixture_id("ZAZU_FIXTURE_BENEFICIARY_ID"))

      expect(response.body["id"]).to be_a(String)
      expect(response.body["external_accounts"]).to be_an(Array)
    end
  end

  describe "#create", vcr: { cassette_name: "beneficiaries/create" } do
    it "creates a beneficiary" do
      response = client.beneficiaries.create(
        beneficiary_type: "business",
        company_name: "Zazu Fixture Beneficiary - spec (zazu-ruby-fixture)",
        email: "fixture-beneficiary-spec@example.com"
      )

      expect(response.status).to eq(201)
      expect(response.body["beneficiary_type"]).to eq("business")
      expect(response.body["external_accounts"]).to eq([])
    end
  end

  describe "#list_external_accounts", vcr: { cassette_name: "beneficiaries/list_external_accounts" } do
    it "returns a Page of the beneficiary's bank accounts" do
      page = client.beneficiaries.list_external_accounts(fixture_id("ZAZU_FIXTURE_CREATED_BENEFICIARY_ID"))

      expect(page).to be_a(Zazu::Page)
      expect(page.data.first["id"]).to eq(fixture_id("ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID"))
      expect(page.data.first["account_number"]).to eq("<ACCOUNT_NUMBER>")
    end
  end

  describe "#get_external_account", vcr: { cassette_name: "beneficiaries/get_external_account" } do
    it "returns a single bank account" do
      response = client.beneficiaries.get_external_account(
        fixture_id("ZAZU_FIXTURE_CREATED_BENEFICIARY_ID"),
        fixture_id("ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID")
      )

      expect(response.body["id"]).to eq(fixture_id("ZAZU_FIXTURE_EXTERNAL_ACCOUNT_ID"))
      expect(response.body).to have_key("default")
    end
  end

  describe "#create_external_account", vcr: { cassette_name: "beneficiaries/create_external_account" } do
    it "adds a bank account to the beneficiary" do
      response = client.beneficiaries.create_external_account(
        fixture_id("ZAZU_FIXTURE_CREATED_BENEFICIARY_ID"),
        account_number: fixture_id("ZAZU_FIXTURE_NEW_ACCOUNT_NUMBER"),
        name: "Fixture Secondary Account"
      )

      expect(response.status).to eq(201)
      expect(response.body["name"]).to eq("Fixture Secondary Account")
      expect(response.body["default"]).to be(false)
    end
  end
end
