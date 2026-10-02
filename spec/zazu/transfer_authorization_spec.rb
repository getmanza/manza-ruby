# frozen_string_literal: true

require "spec_helper"

# Fixed test vector, shared by every SDK in the family. Each SDK's
# signer must produce exactly these hex digests from these inputs.
# The digests were computed independently with:
#
#   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
RSpec.describe Zazu::TransferAuthorization do
  let(:secret) { "whsec_test_vector_secret" }
  let(:fields) do
    {
      payment_id: "0199a1b2-0000-7000-8000-000000000001",
      nonce: "n0nce-0123456789abcdef",
      amount: "2500.0",
      currency_code: "MAD",
      account_id: "0199a1b2-0000-7000-8000-000000000002"
    }
  end

  describe "external-account payee with a client_reference" do
    let(:input) do
      described_class.signature_input(
        **fields,
        payee: described_class.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
        client_reference: "po_1"
      )
    end

    it "builds the versioned, pipe-joined signature input" do
      expect(input).to eq(
        "manza.transfer-authorization.v1|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" \
        "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1"
      )
    end

    it "signs it to the shared vector" do
      expect(described_class.sign(secret: secret, signature_input: input))
        .to eq("6e8eaec0f89a4eb3b22df1133b3d6dfebfa8505c34c58ed0ff192516e4223078")
    end
  end

  describe "own-account payee without a client_reference" do
    let(:input) do
      described_class.signature_input(
        **fields,
        payee: described_class.payee_for(destination_account_id: "0199a1b2-0000-7000-8000-000000000004")
      )
    end

    it "ends with an empty client_reference segment" do
      expect(input).to end_with("|own:0199a1b2-0000-7000-8000-000000000004|")
    end

    it "signs it to the shared vector" do
      expect(described_class.sign(secret: secret, signature_input: input))
        .to eq("af9440b1de1bebb51f381ce43e3d0d27b6a4ccb99dcd548c0b5435ff4fdd1895")
    end
  end

  describe ".signature_input" do
    it "refuses a non-String amount, which would not match the server's decimal string" do
      expect { described_class.signature_input(**fields, amount: 2500, payee: "ext:x") }
        .to raise_error(Zazu::ArgumentError, /amount/)
    end
  end

  describe ".payee_for" do
    it "refuses both ids at once" do
      expect { described_class.payee_for(external_account_id: "a", destination_account_id: "b") }
        .to raise_error(Zazu::ArgumentError)
    end

    it "refuses neither id" do
      expect { described_class.payee_for }.to raise_error(Zazu::ArgumentError)
    end
  end
end
