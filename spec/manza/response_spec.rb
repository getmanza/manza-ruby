# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Response do
  def response_with(headers)
    described_class.new(Faraday::Response.new(status: 200, response_headers: Faraday::Utils::Headers.new(headers)))
  end

  describe "#api_version" do
    it "reads the Manza-Version header" do
      expect(response_with("Manza-Version" => "2026-10-01").api_version).to eq("2026-10-01")
    end

    it "prefers Manza-Version when the server sends both" do
      response = response_with("Manza-Version" => "2026-10-01", "Zazu-Version" => "2026-07-16")

      expect(response.api_version).to eq("2026-10-01")
    end

    it "falls back to the legacy Zazu-Version header" do
      expect(response_with("Zazu-Version" => "2026-07-16").api_version).to eq("2026-07-16")
    end
  end
end
