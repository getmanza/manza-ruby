# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::Base do
  let(:client) { Manza::Client.new(api_key: "k", base_url: "https://staging.manza.example") }

  # WebMock-stubbed unit tests. These exercise the dispatch layer
  # (resource → Base helpers → Client#request) without VCR or real
  # HTTP. They catch the class of bug where a subclass method (e.g.
  # Accounts#get) shadows a Base helper of the same name — that
  # caused every list_page call to misroute and pop with
  # `wrong number of arguments`. We don't need cassettes to surface
  # that; one local stub is enough.
  describe "every resource method dispatches to Client#request" do
    it "GETs through the client without colliding with subclass methods" do
      stub_request(:get, "https://staging.manza.example/api/entity")
        .to_return(status: 200, body: { id: "ent_1", name: "Acme" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = client.entity.get
      expect(response).to be_a(Manza::Response)
      expect(response.body["id"]).to eq("ent_1")
    end

    it "list endpoints reach the Page wrapper" do
      stub_request(:get, %r{https://staging\.manza\.example/api/accounts.*})
        .to_return(
          status: 200,
          body: { data: [{ id: "acc_1" }], has_more: false, next_cursor: nil }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      page = client.accounts.list
      expect(page).to be_a(Manza::Page)
      expect(page.data).to eq([{ "id" => "acc_1" }])
    end

    it "subclass #get methods do not collide with Base helpers" do
      stub_request(:get, "https://staging.manza.example/api/accounts/acc_xyz")
        .to_return(status: 200, body: { id: "acc_xyz" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = client.accounts.get("acc_xyz")
      expect(response.body["id"]).to eq("acc_xyz")
    end

    it "POST endpoints encode the path correctly" do
      stub_request(:post, "https://staging.manza.example/api/invoices/inv_1/cancel")
        .to_return(status: 200, body: { id: "inv_1", status: "cancelled" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = client.invoices.cancel("inv_1")
      expect(response.success?).to be true
    end

    it "DELETE endpoints reach the right URL" do
      stub_request(:delete, "https://staging.manza.example/api/customers/cus_1")
        .to_return(status: 204, body: "")

      response = client.customers.delete("cus_1")
      expect(response.status).to eq(204)
    end

    it "PATCH endpoints send the body" do
      stub_request(:patch, "https://staging.manza.example/api/customers/cus_1")
        .with(body: { email: "new@example.com" }.to_json)
        .to_return(status: 200, body: { id: "cus_1", email: "new@example.com" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = client.customers.update("cus_1", email: "new@example.com")
      expect(response.body["email"]).to eq("new@example.com")
    end

    it "nested-path endpoints percent-encode segments" do
      stub_request(:get, "https://staging.manza.example/api/accounts/acc_1/transactions/tx%201")
        .to_return(status: 200, body: { id: "tx 1" }.to_json,
                   headers: { "Content-Type" => "application/json" })

      response = client.accounts.get_transaction("acc_1", "tx 1")
      expect(response.success?).to be true
    end
  end

  describe "pagination guardrails" do
    it "raises before sending a request when limit > 100" do
      expect { client.accounts.list(limit: 500) }
        .to raise_error(Manza::ArgumentError, /cannot exceed 100/)
      expect(WebMock).not_to have_requested(:get, /accounts/)
    end

    it "raises when limit is not a positive integer" do
      expect { client.accounts.list(limit: 0) }
        .to raise_error(Manza::ArgumentError, /positive integer/)
    end
  end
end
