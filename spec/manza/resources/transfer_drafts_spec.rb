# frozen_string_literal: true

require "spec_helper"

# The deprecated alias of Manza::Resources::Payments. HTTP-free on purpose:
# payments_spec records the cassettes, and a second live authorize while
# recording would hit an already-authorized draft.
RSpec.describe Manza::Client, "#transfer_drafts (deprecated)" do
  let(:client) { manza_client }

  around do |example|
    deprecated = Warning[:deprecated]
    example.run
  ensure
    Warning[:deprecated] = deprecated
  end

  it "is the payments resource, so it calls /api/payments" do
    Warning[:deprecated] = false

    expect(client.transfer_drafts).to equal(client.payments)
  end

  it "keeps the constant, naming the same class" do
    Warning[:deprecated] = false

    expect(Manza::Resources.const_get(:TransferDrafts)).to equal(Manza::Resources::Payments)
  end

  it "warns once deprecation warnings are on" do
    Warning[:deprecated] = true

    expect { client.transfer_drafts }.to output(/transfer_drafts is deprecated.*payments/).to_stderr
  end

  it "stays silent by default" do
    Warning[:deprecated] = false

    expect { client.transfer_drafts }.not_to output.to_stderr
  end
end
