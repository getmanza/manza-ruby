# frozen_string_literal: true

require "rake"

# The Rakefile loaded once into its own application: loading it again
# would redefine the constants in lib/tasks/fixtures.rake.
STAGING_STATE_RAKE = Rake::Application.new.tap do |app|
  previous = Rake.application
  Rake.application = app
  Rake.load_rakefile(File.expand_path("../../Rakefile", __dir__))
ensure
  Rake.application = previous
end

RSpec.describe "staging fixture state tasks", type: :task do
  let(:creator_key) { "sk_fake_CREATORa-not-a-real-key-creator" }
  let(:authorizer_key) { "sk_fake_AUTHORIZ-not-a-real-key-authorizer" }
  let(:staging_url) { "https://staging.manza.example" }
  let(:declared) { JSON.parse(File.read(File.expand_path("../../lib/tasks/staging_fixture_state.json", __dir__))) }

  around do |example|
    env = {
      "MANZA_STAGING_API_KEY" => creator_key,
      "MANZA_STAGING_AUTHORIZER_API_KEY" => authorizer_key,
      "MANZA_STAGING_URL" => staging_url,
      "CIDR" => nil
    }
    saved = env.keys.to_h { |k| [k, ENV.fetch(k, nil)] }
    previous_rake = Rake.application
    env.each { |k, v| ENV[k] = v }
    Rake.application = STAGING_STATE_RAKE
    example.run
  ensure
    Rake.application = previous_rake
    saved.each { |k, v| ENV[k] = v }
  end

  def run_task(name)
    task = Rake::Task[name]
    task.reenable
    task.invoke
  end

  def stub_ipv4(body = "198.51.100.10")
    stub_request(:get, "https://api.ipify.org/").to_return(status: 200, body: body)
  end

  def stub_ipv6(body = "2001:db8:fe65:a300:a843:b24a:5e3:3749")
    stub_request(:get, "https://api6.ipify.org/").to_return(status: 200, body: body)
  end

  describe "fixtures:staging:ensure_arguments" do
    def arguments
      JSON.parse(capture_stdout { run_task("fixtures:staging:ensure_arguments") })
    end

    def capture_stdout
      original = $stdout
      $stdout = StringIO.new
      yield
      $stdout.string
    ensure
      $stdout = original
    end

    it "declares transfers:authorize on the creator key too" do
      # transfer_drafts/authorize_same_key records the creating key refused
      # as same_key_forbidden; without the scope it records insufficient_scope.
      expect(declared["creator_key_scopes"]).to include("transfers:authorize")
    end

    it "emits both 16-character key prefixes and the declared state" do
      stub_ipv4
      stub_ipv6

      args = arguments

      expect(args["creator_key_prefix"]).to eq("sk_fake_CREATORa")
      expect(args["authorizer_key_prefix"]).to eq("sk_fake_AUTHORIZ")
      expect(args["desired"]).to include(declared)
    end

    it "adds the machine's IPv4 /32 and IPv6 /64 to both keys' CIDRs" do
      stub_ipv4
      stub_ipv6

      desired = arguments["desired"]

      expected = ["198.51.100.10/32", "2001:db8:fe65:a300::/64"]
      expect(desired["creator_key_cidrs"]).to eq(expected)
      expect(desired["authorizer_key_cidrs"]).to eq(expected)
    end

    it "uses CIDR instead of looking the addresses up" do
      ENV["CIDR"] = "203.0.113.7/32, 2001:db8::/64"

      desired = arguments["desired"]

      expect(desired["creator_key_cidrs"]).to eq(["203.0.113.7/32", "2001:db8::/64"])
      expect(desired["authorizer_key_cidrs"]).to eq(["203.0.113.7/32", "2001:db8::/64"])
      expect(a_request(:get, /ipify/)).not_to have_been_made
    end

    it "keeps only the IPv4 address when the machine has no IPv6" do
      stub_ipv4
      stub_request(:get, "https://api6.ipify.org/").to_raise(Errno::ENETUNREACH)

      desired = nil
      expect { desired = arguments["desired"] }.to output(/api6\.ipify\.org/).to_stderr
      expect(desired["creator_key_cidrs"]).to eq(["198.51.100.10/32"])
    end

    it "skips a lookup that does not answer with an address" do
      stub_request(:get, "https://api.ipify.org/").to_return(status: 503, body: "<html>Service Unavailable</html>")
      stub_ipv6

      desired = nil
      expect { desired = arguments["desired"] }.to output(/api\.ipify\.org/).to_stderr
      expect(desired["creator_key_cidrs"]).to eq(["2001:db8:fe65:a300::/64"])
    end

    it "aborts, naming CIDR, when neither address can be looked up" do
      stub_request(:get, "https://api.ipify.org/").to_raise(SocketError)
      stub_request(:get, "https://api6.ipify.org/").to_raise(Errno::ENETUNREACH)

      expect { run_task("fixtures:staging:ensure_arguments") }
        .to raise_error(SystemExit).and output(/CIDR=/).to_stderr
    end

    it "never prints more than 16 characters of a key" do
      stub_ipv4
      stub_ipv6

      output = capture_stdout { run_task("fixtures:staging:ensure_arguments") }

      expect(output).not_to include(creator_key[0, 17])
      expect(output).not_to include(authorizer_key[0, 17])
    end

    it "aborts when a key is missing from .env" do
      ENV["MANZA_STAGING_AUTHORIZER_API_KEY"] = ""

      expect { run_task("fixtures:staging:ensure_arguments") }
        .to raise_error(SystemExit).and output(/MANZA_STAGING_AUTHORIZER_API_KEY/).to_stderr
    end
  end

  describe "fixtures:preflight" do
    let(:authorizer_url) { "#{staging_url}/api/transfer_authorizer" }

    it "passes when the authorizer is active" do
      stub = stub_request(:get, authorizer_url)
             .with(headers: { "Authorization" => "Bearer #{authorizer_key}" })
             .to_return(status: 200, body: { status: "active", suspension_reason: nil }.to_json)

      expect { run_task("fixtures:preflight") }.not_to raise_error
      expect(stub).to have_been_requested
    end

    it "aborts with the status, the reason and the fix when the authorizer is suspended" do
      stub_request(:get, authorizer_url)
        .to_return(status: 200, body: { status: "suspended", suspension_reason: "endpoint_disabled" }.to_json)

      expect { run_task("fixtures:preflight") }.to raise_error(SystemExit).and output(
        "authorizer suspended/endpoint_disabled: run sdk_fixtures_ensure (AGENTS.md → Staging fixture state)\n"
      ).to_stderr
    end

    it "aborts with the HTTP status when the authorizer cannot be read" do
      stub_request(:get, authorizer_url).to_return(status: 404, body: "<html>Not Found</html>")

      expect { run_task("fixtures:preflight") }.to raise_error(SystemExit).and output(
        "authorizer not enrolled (HTTP 404)/none: run sdk_fixtures_ensure (AGENTS.md → Staging fixture state)\n"
      ).to_stderr
    end

    it "names the API error type when the key is refused" do
      stub_request(:get, authorizer_url).to_return(
        status: 403, body: { error: { message: "This API key cannot be used from this IP address", type: "ip_not_allowed" } }.to_json
      )

      expect { run_task("fixtures:preflight") }.to raise_error(SystemExit).and output(
        "authorizer HTTP 403/ip_not_allowed: run sdk_fixtures_ensure (AGENTS.md → Staging fixture state)\n"
      ).to_stderr
    end

    it "points at the authorizer key when it does not authenticate" do
      stub_request(:get, authorizer_url).to_return(
        status: 401, body: { error: { message: "Invalid API key", type: "authentication_error" } }.to_json
      )

      expect { run_task("fixtures:preflight") }.to raise_error(SystemExit).and output(
        "authorizer HTTP 401/authentication_error: check MANZA_STAGING_AUTHORIZER_API_KEY in .env\n"
      ).to_stderr
    end

    it "aborts in one line when staging cannot be reached" do
      stub_request(:get, authorizer_url).to_raise(SocketError.new("getaddrinfo: nodename nor servname provided"))

      expect { run_task("fixtures:preflight") }.to raise_error(SystemExit).and output(
        "authorizer unreachable/SocketError: getaddrinfo: nodename nor servname provided: check MANZA_STAGING_URL and the network\n"
      ).to_stderr
    end

    it "aborts in one line when MANZA_STAGING_URL has no scheme" do
      ENV["MANZA_STAGING_URL"] = "ma.manza.dev"

      expect { run_task("fixtures:preflight") }
        .to raise_error(SystemExit).and output(/\Aauthorizer unreachable.*check MANZA_STAGING_URL and the network\n\z/).to_stderr
    end

    it "aborts when MANZA_STAGING_URL is missing" do
      ENV["MANZA_STAGING_URL"] = ""

      expect { run_task("fixtures:preflight") }
        .to raise_error(SystemExit).and output(/MANZA_STAGING_URL/).to_stderr
    end

    it "runs before fixtures:record tears anything down" do
      expect(Rake::Task["fixtures:record"].prerequisites).to eq(%w[preflight teardown seed])
    end

    it "runs before fixtures:seed" do
      expect(Rake::Task["fixtures:seed"].prerequisites).to eq(%w[preflight])
    end
  end
end
