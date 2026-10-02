# frozen_string_literal: true

# VCR configuration. Cassettes live in spec/fixtures/cassettes/
# and are committed to the repo. Each release ships them as a
# tarball release asset so other-language SDKs can reuse the same
# canonical interaction record.
#
# Recording:
#   - Default mode is :none — CI and local runs play back cassettes
#     and fail loudly on any unexpected HTTP request.
#   - Set VCR_RECORD=all or VCR_RECORD=new_episodes to refresh.
#     Common usage: `bundle exec rake fixtures:record` which sets
#     VCR_RECORD=all and runs the entire spec suite.
#
# Sensitive data is filtered before cassettes hit disk:
#   - Authorization bearer tokens → "<ZAZU_API_KEY>"
#   - X-Request-Id response headers → "<REQUEST_ID>"
#   - Zazu-Version / Manza-Version response headers → "<ZAZU_VERSION>"
#   - `signature` in transfer-authorization request bodies → "<SIGNATURE>"
#   - List endpoints: non-fixture entries dropped from the response
#     so we don't ship real customer PII / live webhook URLs from the
#     staging entity into a public repo.
#   - Sensitive response fields by name (recursive, any nesting depth):
#       signing_secret → "<WEBHOOK_SIGNING_SECRET>"
#       rib            → "<RIB>"
#       account_number → "<ACCOUNT_NUMBER>"
#       bank_identifier → "<BANK_IDENTIFIER>"
#       next_cursor    → "<NEXT_CURSOR>" (encodes a real non-fixture record)
# Even if a developer pastes a real key into a test or pulls one
# from .env, the committed cassette is scrubbed.

require "json"

# Real fixture IDs from the developer's .env, used to identify which
# entries in a list-endpoint response are ours (i.e. seeded by
# `rake fixtures:seed`) vs anything else on the staging entity.
# Only ours survive cassette recording — everything else is real
# customer / invoice / webhook data and would leak PII to a public
# repo if committed.
FIXTURE_REAL_IDS = Zazu::SpecFixtures::IDS.keys.filter_map { |k| ENV.fetch(k, nil) }.reject(&:empty?).to_set

# VCR scrubber that removes non-fixture records from list-endpoint
# response bodies and strips `signing_secret` from webhook responses.
# Runs in a `before_record` hook (before the filter_sensitive_data
# replacements), so IDs are still real UUIDs at this point — that's
# why we compare against FIXTURE_REAL_IDS instead of placeholders.
def scrub_response_body!(interaction)
  body = interaction.response.body
  return unless body.is_a?(String) && !body.empty?

  parsed =
    begin
      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end
  return if parsed.nil?

  changed = false

  if parsed.is_a?(Hash) && parsed["data"].is_a?(Array)
    kept = parsed["data"].select do |entry|
      next false unless entry.is_a?(Hash) && entry["id"].is_a?(String)

      FIXTURE_REAL_IDS.include?(entry["id"])
    end
    if kept.size != parsed["data"].size
      parsed["data"] = kept
      changed = true
    end
  end

  changed = true if scrub_sensitive_fields!(parsed)

  interaction.response.body = JSON.generate(parsed) if changed
end

# Field name → placeholder. Add a new entry here whenever the API
# starts returning a value we don't want committed to a public repo.
# Matched by exact JSON key at any nesting depth.
SENSITIVE_FIELD_PLACEHOLDERS = {
  "signing_secret" => "<WEBHOOK_SIGNING_SECRET>",
  "rib" => "<RIB>", # Moroccan bank account / routing identifier
  # Beneficiary bank accounts — staging holds real bank numbers.
  "account_number" => "<ACCOUNT_NUMBER>",
  "bank_identifier" => "<BANK_IDENTIFIER>",
  # Cursor encodes a real non-fixture record's timestamp + UUID; it
  # churns on every re-record and points at staging internals.
  "next_cursor" => "<NEXT_CURSOR>"
}.freeze

# Recursively replace sensitive field values with placeholders.
# Returns true if anything was changed.
def scrub_sensitive_fields!(value)
  case value
  when Hash
    changed = false
    value.each do |k, v|
      placeholder = SENSITIVE_FIELD_PLACEHOLDERS[k]
      if placeholder && v.is_a?(String) && v != placeholder
        value[k] = placeholder
        changed = true
      elsif scrub_sensitive_fields!(v)
        changed = true
      end
    end
    changed
  when Array
    # Don't use `any?` — it short-circuits and leaves subsequent
    # elements unscrubbed. Walk every element.
    changed = false
    value.each { |v| changed = true if scrub_sensitive_fields!(v) }
    changed
  else
    false
  end
end

VCR.configure do |config|
  config.cassette_library_dir = File.expand_path("../fixtures/cassettes", __dir__)
  config.hook_into :webmock
  config.configure_rspec_metadata!

  # Drop non-fixture records from list responses + redact webhook
  # signing secrets before VCR writes the cassette to disk.
  config.before_record do |interaction|
    scrub_response_body!(interaction)
  end

  config.default_cassette_options = {
    record: :none,
    match_requests_on: %i[method uri body],
    serialize_with: :yaml
  }

  if ENV["VCR_RECORD"]
    record_mode = ENV["VCR_RECORD"].to_sym
    config.default_cassette_options[:record] = record_mode

    # When recording, allow real HTTP through WebMock.
    WebMock.allow_net_connect!
  end

  # Scrubbers — run on every interaction before write.
  config.filter_sensitive_data("<ZAZU_API_KEY>") do |interaction|
    auth = interaction.request.headers["Authorization"]
    next nil unless auth.is_a?(Array) && auth.first

    auth.first.delete_prefix("Bearer ")
  end

  config.filter_sensitive_data("<REQUEST_ID>") do |interaction|
    interaction.response.headers["X-Request-Id"]&.first
  end

  config.filter_sensitive_data("<ZAZU_VERSION>") do |interaction|
    interaction.response.headers["Zazu-Version"]&.first
  end

  config.filter_sensitive_data("<ZAZU_VERSION>") do |interaction|
    interaction.response.headers["Manza-Version"]&.first
  end

  # The authorize signature is an HMAC over the real nonce under the
  # real authorizer secret. It lives in the *request* body, which the
  # field scrubber above does not walk.
  config.filter_sensitive_data("<SIGNATURE>") do |interaction|
    next nil unless interaction.request.uri.end_with?("/authorize")

    JSON.parse(interaction.request.body.to_s)["signature"]
  rescue JSON::ParserError
    nil
  end

  # Scrub fixture IDs out of URLs and bodies so cassettes replay
  # deterministically on machines without an .env (CI, contributors).
  # The placeholder must match the spec's `ENV.fetch` fallback exactly
  # — see spec/support/fixture_ids.rb for the canonical table.
  Zazu::SpecFixtures::IDS.each do |env_var, placeholder|
    real = ENV.fetch(env_var, nil)
    next if real.nil? || real.empty?

    config.filter_sensitive_data(placeholder) { real }
  end
end
