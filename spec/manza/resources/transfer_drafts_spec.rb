# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Resources::TransferDrafts do
  let(:client) { manza_client }

  describe "#create", vcr: { cassette_name: "transfer_drafts/create" } do
    it "creates a draft carrying the client_reference" do
      response = client.transfer_drafts.create(
        account_id: fixture_id("MANZA_FIXTURE_ACCOUNT_ID"),
        beneficiary_id: fixture_id("MANZA_FIXTURE_BENEFICIARY_ID"),
        amount: "150.00",
        payment_reference: "SDK fixture",
        client_reference: fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE")
      )

      expect(response.status).to eq(201)
      expect(response.body["status"]).to eq("requested")
      expect(response.body["client_reference"]).to eq(fixture_id("MANZA_FIXTURE_CLIENT_REFERENCE"))
      expect(response.body).to have_key("authorization")
      expect(response.body["transfer"]).to be_nil
    end
  end

  describe "#create with a duplicate client_reference", vcr: { cassette_name: "transfer_drafts/create_duplicate" } do
    it "raises ConflictError naming the existing draft" do
      expect do
        client.transfer_drafts.create(
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

  describe "#get", vcr: { cassette_name: "transfer_drafts/get" } do
    it "returns a single transfer draft" do
      response = client.transfer_drafts.get(fixture_id("MANZA_FIXTURE_TRANSFER_DRAFT_ID"))

      expect(response.body["id"]).to be_a(String)
      expect(response.body).to have_key("status")
      expect(response.body).to have_key("transfer")
    end
  end

  describe "#authorize with a blank signature" do
    it "raises locally without calling the API" do
      expect { client.transfer_drafts.authorize("draft", authorization_id: "auth", signature: " ") }
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
             vcr: { cassette_name: "transfer_drafts/authorize_bad_signature", match_requests_on: %i[method uri body_without_signature] } do
      it "raises ValidationError invalid_signature" do
        expect do
          manza_authorizer_client.transfer_drafts.authorize(
            fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_DRAFT_ID"),
            authorization_id: fixture_id("MANZA_FIXTURE_BAD_SIGNATURE_AUTHORIZATION_ID"),
            signature: "0" * 64
          )
        end.to raise_error(Manza::ValidationError) { |e| expect(e.type).to eq("invalid_signature") }
      end
    end

    describe "#authorize with the creating key",
             vcr: { cassette_name: "transfer_drafts/authorize_same_key", match_requests_on: %i[method uri body_without_signature] } do
      it "raises ForbiddenError same_key_forbidden" do
        expect do
          client.transfer_drafts.authorize(
            fixture_id("MANZA_FIXTURE_AUTHORIZABLE_DRAFT_ID"),
            authorization_id: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
            signature: "0" * 64
          )
        end.to raise_error(Manza::ForbiddenError) { |e| expect(e.type).to eq("same_key_forbidden") }
      end
    end

    describe "#authorize",
             vcr: { cassette_name: "transfer_drafts/authorize", match_requests_on: %i[method uri body_without_signature] } do
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

        response = manza_authorizer_client.transfer_drafts.authorize(
          draft_id,
          authorization_id: fixture_id("MANZA_FIXTURE_AUTHORIZABLE_AUTHORIZATION_ID"),
          signature: Manza::TransferAuthorization.sign(secret: authorizer_signing_secret, signature_input: input)
        )

        expect(response.status).to eq(200)
        expect(response.body["id"]).to eq(draft_id)
        expect(response.body.dig("authorization", "status")).to eq("authorized")
      end
    end
  end

  describe "#decline", vcr: { cassette_name: "transfer_drafts/decline" } do
    it "declines the challenge" do
      response = manza_authorizer_client.transfer_drafts.decline(
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
