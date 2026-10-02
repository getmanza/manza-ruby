# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::Entity, vcr: { cassette_name: "entity/get" } do
  let(:client) { manza_client }

  describe "#get" do
    it "returns the current entity" do
      response = client.entity.get
      expect(response).to be_a(Manza::Response)
      expect(response.success?).to be true
      expect(response.body).to be_a(Hash)
      expect(response.body["id"]).to be_a(String)
      expect(response.body["name"]).to be_a(String)
    end
  end
end
