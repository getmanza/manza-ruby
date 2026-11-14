# frozen_string_literal: true

require "spec_helper"

# Fixed test vector, shared by every SDK in the family. Each SDK's
# signer must produce exactly these hex digests from these inputs.
# The digests were computed independently with:
#
#   printf '%s' '<input>' | openssl dgst -sha256 -hmac 'whsec_test_vector_secret'
RSpec.describe Manza::TransferAuthorization do
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

  it "signs version v2" do
    expect(described_class::SIGNATURE_VERSION).to eq("manza.transfer-authorization.v2")
  end

  describe "external-account payee with a client_reference and a transfer_method" do
    let(:input) do
      described_class.signature_input(
        **fields,
        payee: described_class.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
        client_reference: "po_1",
        transfer_method: "eft"
      )
    end

    it "builds the versioned, pipe-joined signature input with the transfer_method last" do
      expect(input).to eq(
        "manza.transfer-authorization.v2|0199a1b2-0000-7000-8000-000000000001|n0nce-0123456789abcdef|" \
        "2500.0|MAD|0199a1b2-0000-7000-8000-000000000002|ext:0199a1b2-0000-7000-8000-000000000003|po_1|eft"
      )
    end

    it "signs it to the shared vector" do
      expect(described_class.sign(secret: secret, signature_input: input))
        .to eq("904da7d0b73b2c919ffa1ae64d262ce5825ee4d2c8420fd70a3d257353e6c43a")
    end
  end

  describe "a nil transfer_method" do
    let(:input) do
      described_class.signature_input(
        **fields,
        payee: described_class.payee_for(external_account_id: "0199a1b2-0000-7000-8000-000000000003"),
        client_reference: "po_1",
        transfer_method: nil
      )
    end

    it "ends with an empty transfer_method segment" do
      expect(input).to end_with("|ext:0199a1b2-0000-7000-8000-000000000003|po_1|")
    end

    it "signs it to the shared vector" do
      expect(described_class.sign(secret: secret, signature_input: input))
        .to eq("029dd12924a846d7af2f4aecb61e4f4f9bd64d37315230864fb03917adc29edf")
    end
  end

  describe "own-account payee without a client_reference or a transfer_method" do
    let(:input) do
      described_class.signature_input(
        **fields,
        payee: described_class.payee_for(destination_account_id: "0199a1b2-0000-7000-8000-000000000004"),
        transfer_method: nil
      )
    end

    it "ends with two empty segments" do
      expect(input).to end_with("|own:0199a1b2-0000-7000-8000-000000000004||")
    end

    it "signs it to the shared vector" do
      expect(described_class.sign(secret: secret, signature_input: input))
        .to eq("a21ccf43b94f23d7a595a36bd788c27c7adbc5686a5ad4427b22d9957568c9fb")
    end
  end

  describe ".signature_input" do
    it "refuses a non-String amount, which would not match the server's decimal string" do
      expect { described_class.signature_input(**fields, amount: 2500, payee: "ext:x", transfer_method: nil) }
        .to raise_error(Manza::ArgumentError, /amount/)
    end

    # A v1 call (no transfer_method) fails here, not as a failed signature
    # attempt at the API, where five of them fail the challenge.
    it "requires transfer_method, nil included" do
      expect { described_class.signature_input(**fields, payee: "ext:x") }
        .to raise_error(ArgumentError, /transfer_method/)
    end
  end

  describe ".payee_for" do
    it "refuses both ids at once" do
      expect { described_class.payee_for(external_account_id: "a", destination_account_id: "b") }
        .to raise_error(Manza::ArgumentError)
    end

    it "refuses neither id" do
      expect { described_class.payee_for }.to raise_error(Manza::ArgumentError)
    end
  end
end
