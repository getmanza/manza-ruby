# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::Invoices do
  let(:client) { manza_client }

  describe "#list", vcr: { cassette_name: "invoices/list" } do
    it "returns a Page" do
      page = client.invoices.list
      expect(page).to be_a(Manza::Page)
    end
  end

  describe "#get", vcr: { cassette_name: "invoices/get" } do
    it "returns a single invoice" do
      response = client.invoices.get(fixture_id("MANZA_FIXTURE_INVOICE_ID"))
      expect(response.body["id"]).to be_a(String)
    end
  end

  describe "#create", vcr: { cassette_name: "invoices/create" } do
    it "creates an invoice paid into the account, asking for a payment link" do
      response = client.invoices.create(
        customer_id: fixture_id("MANZA_FIXTURE_CUSTOMER_ID"),
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        currency_code: "MAD",
        issue_date: "2026-05-03",
        due_date: "2026-06-03",
        generate_payment_link: true,
        items: [
          { description: "SDK fixture line", quantity: 1, unit_price: "100.00" }
        ]
      )

      expect(response.status).to eq(201)
      expect(response.body["generate_payment_link"]).to be(true)
      expect(response.body.dig("account", "id")).to eq(fixture_id("MANZA_FIXTURE_ACCOUNT_ID"))
    end
  end

  # An invoice is paid into one of the entity's accounts: a create without
  # one is refused as not approvable (`type` "state_error"). An account_id
  # that is not the entity's is refused with `param` "account_id".
  describe "#create without an account_id", vcr: { cassette_name: "invoices/create_without_account" } do
    it "raises ValidationError" do
      expect do
        client.invoices.create(
          customer_id: fixture_id("MANZA_FIXTURE_CUSTOMER_ID"),
          currency_code: "MAD",
          issue_date: "2026-05-03",
          due_date: "2026-06-03",
          items: [
            { description: "SDK fixture line", quantity: 1, unit_price: "100.00" }
          ]
        )
      end.to raise_error(Manza::ValidationError) { |e|
        expect(e.status).to eq(422)
        expect(e.type).to eq("state_error")
      }
    end
  end

  describe "#update", vcr: { cassette_name: "invoices/update" } do
    it "updates an invoice" do
      response = client.invoices.update(
        fixture_id("MANZA_FIXTURE_INVOICE_ID"),
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        notes: "updated by SDK fixture spec",
        generate_payment_link: true
      )

      expect(response.status).to eq(200)
      expect(response.body["generate_payment_link"]).to be(true)
      expect(response.body.dig("account", "id")).to eq(fixture_id("MANZA_FIXTURE_ACCOUNT_ID"))
    end
  end

  # The state-transition specs (send/mark_as_paid/cancel/
  # credit_note) need an invoice in the
  # `approved` state. The public API does not currently expose a
  # transition into that state — the back-office UI is the only
  # path. These specs are pending and will be enabled once the API
  # surfaces an approve endpoint or we add an admin-side helper.
  describe "#send_invoice", skip: "pending API approve endpoint" do
    it "sends the invoice"
  end

  describe "#mark_as_paid", skip: "pending API approve endpoint" do
    it "marks an invoice as paid"
  end

  describe "#cancel", skip: "pending API approve endpoint" do
    it "cancels an invoice"
  end

  describe "#credit_note", skip: "pending API approve endpoint" do
    it "creates a credit note"
  end

  describe "#delete", vcr: { cassette_name: "invoices/delete" } do
    it "deletes an invoice" do
      response = client.invoices.delete(fixture_id("MANZA_FIXTURE_DELETABLE_INVOICE_ID"))
      expect(response.status).to eq(204)
    end
  end

  it "has no create_payment_link: generate_payment_link on create or update replaced it" do
    expect(client.invoices).not_to respond_to(:create_payment_link)
  end
end
