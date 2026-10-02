# frozen_string_literal: true

# Tiny test-side helper. Wires a Zazu::Client up to the staging
# base URL with whatever API key is in ENV. During cassette playback
# the key value doesn't matter (it's scrubbed in cassettes anyway);
# during recording, it has to be a real staging key.
module ClientHelpers
  STAGING_BASE_URL = "https://ma.manza.dev"

  def zazu_client(**overrides)
    Zazu::Client.new(
      api_key: ENV.fetch("ZAZU_STAGING_API_KEY", "test-key-only-used-during-recording"),
      base_url: ENV.fetch("ZAZU_STAGING_URL", STAGING_BASE_URL),
      **overrides
    )
  end

  # A second key holding `transfers:authorize`. The API refuses to let
  # the key that created a transfer draft authorize or decline it.
  def zazu_authorizer_client
    zazu_client(api_key: ENV.fetch("ZAZU_STAGING_AUTHORIZER_API_KEY", "test-authorizer-key-only-used-during-recording"))
  end

  # The authorizer webhook endpoint's signing secret. Only needed while
  # recording: replay matches the authorize requests on method + URI.
  def authorizer_signing_secret
    ENV.fetch("ZAZU_STAGING_AUTHORIZER_SECRET", "test-secret-only-used-during-recording")
  end
end
