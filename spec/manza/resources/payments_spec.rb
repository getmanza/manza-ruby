# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::Payments do
  let(:client) { manza_client }

  describe "#create", vcr: { cassette_name: "payments/create" } do
    it "creates a draft carrying the client_reference" do
      response = client.payments.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        beneficiary_id: fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
        amount: "10.00",
        payment_reference: "SDK fixture",
        internal_notes: "[zazu-ruby-fixture] create spec - do not approve",
        client_reference: fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE")
      )

      expect(response.status).to eq(201)
      expect(response.body["status"]).to eq("requested")
      expect(response.body["client_reference"]).to eq(fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE"))
      # Inside the envelope: the challenge went to the authorizer.
      expect(response.body.dig("authorization", "status")).to eq("pending")
      expect(response.body["transfer"]).to be_nil
    end
  end

  describe "#create with a duplicate client_reference", vcr: { cassette_name: "payments/create_duplicate" } do
    it "raises ConflictError naming the existing draft" do
      expect do
        client.payments.create(
          account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
          beneficiary_id: fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
          amount: "10.00",
          client_reference: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
        )
      end.to raise_error(Manza::ConflictError) { |e|
        expect(e.type).to eq("duplicate_client_reference")
        expect(e.payment_id).to eq(fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"))
      }
    end
  end

  describe "#get", vcr: { cassette_name: "payments/get" } do
    it "returns a single payment" do
      response = client.payments.get(fixture_id("MANZA_FIXTURE_TRANSFER_DRAFT_ID"))

      expect(response.body["id"]).to be_a(String)
      expect(response.body).to have_key("status")
      expect(response.body).to have_key("transfer")
    end
  end

  describe "#get for a draft refused at create time", vcr: { cassette_name: "payments/get_refused" } do
    it "carries the refused authorization and its reason" do
      response = client.payments.get(fixture_id("MANZA_FIXTURE_REFUSED_DRAFT_ID"))

      expect(response.body["id"]).to eq(fixture_id("MANZA_FIXTURE_REFUSED_DRAFT_ID"))
      expect(response.body.dig("authorization", "status")).to eq("refused")
      expect(response.body.dig("authorization", "refusal_reason")).to eq("over_transfer_limit")
    end
  end

  describe "#authorize with a blank signature" do
    it "raises locally without calling the API" do
      expect { client.payments.authorize("draft", authorization_id: "auth", signature: " ") }
        .to raise_error(Manza::ArgumentError, /signature/)
    end
  end

  # Order matters while recording: five consecutive bad signatures
  # suspend the authorizer, and only a valid authorize resets the
  # streak. So the bad signature records before the valid one.
  #
  # The authorize cassettes match the body minus `signature`: the
  # recorded signature is an HMAC over the real nonce and secret
  # (scrubbed to <SIGNATURE>), which replay cannot reproduce. The signer
  # itself is proven by spec/manza/transfer_authorization_spec.rb.
  describe "machine authorization", order: :defined do
    describe "#authorize with a bad signature",
             vcr: { cassette_name: "payments/authorize_bad_signature", match_requests_on: %i[method uri body_without_signature] } do
      it "raises ValidationError invalid_signature" do
        expect do
          manza_authorizer_client.payments.authorize(
            fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID"),
            authorization_id: fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID"),
            signature: "0" * 64
          )
        end.to raise_error(Manza::ValidationError) { |e| expect(e.type).to eq("invalid_signature") }
      end
    end

    describe "#authorize with the creating key",
             vcr: { cassette_name: "payments/authorize_same_key", match_requests_on: %i[method uri body_without_signature] } do
      it "raises ForbiddenError same_key_forbidden" do
        expect do
          client.payments.authorize(
            fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"),
            authorization_id: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
            signature: "0" * 64
          )
        end.to raise_error(Manza::ForbiddenError) { |e| expect(e.type).to eq("same_key_forbidden") }
      end
    end

    describe "#authorize",
             vcr: { cassette_name: "payments/authorize", match_requests_on: %i[method uri body_without_signature] } do
      it "executes the draft" do
        draft_id = fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID")
        input = Manza::TransferAuthorization.signature_input(
          payment_id: draft_id,
          nonce: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_NONCE"),
          amount: "10.0",
          currency_code: "MAD",
          account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
          payee: Manza::TransferAuthorization.payee_for(
            external_account_id: fixture_id("MANZA_FIXTURE_TRUSTED_EXTERNAL_ACCOUNT_ID")
          ),
          client_reference: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_CLIENT_REFERENCE")
        )

        response = manza_authorizer_client.payments.authorize(
          draft_id,
          authorization_id: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
          signature: Manza::TransferAuthorization.sign(secret: authorizer_signing_secret, signature_input: input)
        )

        expect(response.status).to eq(200)
        expect(response.body["id"]).to eq(draft_id)
        expect(response.body.dig("authorization", "status")).to eq("authorized")
      end
    end

    # The fresh bank account was never trusted; with "Approve transfers to
    # new payees" on, the authorizer approves it and the signature trusts it.
    describe "#authorize a transfer to a new payee",
             vcr: { cassette_name: "payments/authorize_new_payee", match_requests_on: %i[method uri body_without_signature] } do
      it "executes the draft" do
        draft_id = fixture_id("MANZA_FIXTURE_NEW_PAYEE_DRAFT_ID")
        input = Manza::TransferAuthorization.signature_input(
          payment_id: draft_id,
          nonce: fixture_id("MANZA_FIXTURE_NEW_PAYEE_NONCE"),
          amount: "10.0",
          currency_code: "MAD",
          account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
          payee: Manza::TransferAuthorization.payee_for(external_account_id: fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")),
          client_reference: fixture_id("MANZA_FIXTURE_NEW_PAYEE_CLIENT_REFERENCE")
        )

        response = manza_authorizer_client.payments.authorize(
          draft_id,
          authorization_id: fixture_id("MANZA_FIXTURE_NEW_PAYEE_AUTHORIZATION_ID"),
          signature: Manza::TransferAuthorization.sign(secret: authorizer_signing_secret, signature_input: input)
        )

        expect(response.status).to eq(200)
        expect(response.body["id"]).to eq(draft_id)
        expect(response.body.dig("authorization", "status")).to eq("authorized")
      end
    end

    # Records after the new-payee authorize: its signature trusted the payee.
    describe "the new payee's bank account afterwards", vcr: { cassette_name: "beneficiaries/get_external_account_trusted" } do
      it "is trusted" do
        response = client.beneficiaries.get_external_account(
          fixture_id("MANZA_FIXTURE_CREATED_BENEFICIARY_ID"),
          fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID")
        )

        expect(response.body["id"]).to eq(fixture_id("MANZA_FIXTURE_EXTERNAL_ACCOUNT_ID"))
        expect(response.body["trusted"]).to be(true)
      end
    end
  end

  describe "#decline", vcr: { cassette_name: "payments/decline" } do
    it "declines the challenge" do
      response = manza_authorizer_client.payments.decline(
        fixture_id("MANZA_FIXTURE_DECLINABLE_DRAFT_ID"),
        authorization_id: fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"),
        reason: "SDK fixture"
      )

      expect(response.status).to eq(200)
      expect(response.body["id"]).to eq(fixture_id("MANZA_FIXTURE_DECLINABLE_AUTHORIZATION_ID"))
      expect(response.body["status"]).to eq("declined")
      expect(response.body["declined_at"]).to be_a(String)
    end
  end
end
