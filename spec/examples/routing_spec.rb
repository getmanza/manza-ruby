# frozen_string_literal: true

require "spec_helper"
require_relative "../../examples/transfer_authorizer/routing"

RSpec.describe TransferAuthorizer::Routing do
  describe ".describe" do
    it "says the challenge went to the authorizer when it is pending" do
      expect(described_class.describe({ "status" => "pending" })).to include("challenge sent")
    end

    it "explains every create-time refusal reason in words" do
      described_class::REFUSAL_REASONS.each do |reason, words|
        line = described_class.describe({ "status" => "refused", "refusal_reason" => reason })

        expect(line).to include("approvers", "refused", reason, words)
      end
    end

    it "explains the new-payee refusals" do
      expect(described_class.describe({ "status" => "refused", "refusal_reason" => "unrestricted_api_key" }))
        .to include("IP allowlist")
      expect(described_class.describe({ "status" => "refused", "refusal_reason" => "over_new_payee_limit" }))
        .to include("limit per transfer to a new payee")
    end

    it "points at the docs for a reason it does not know" do
      expect(described_class.describe({ "status" => "refused", "refusal_reason" => "something_new" }))
        .to include("something_new", "transfer authorization docs")
    end

    it "says no authorizer was enrolled when there is no authorization" do
      expect(described_class.describe(nil)).to include("no transfer authorizer")
    end
  end
end
