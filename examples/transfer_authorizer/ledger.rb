# frozen_string_literal: true

require "json"

module TransferAuthorizer
  # Your own record of the transfers you created, keyed by the
  # client_reference you generated. A JSON file, so the creator
  # (create_transfer.rb) and the authorizer (config.ru) can run as two
  # processes. Swap it for your database in production.
  #
  #   { "po_8812" => { "payment_id" => "...", "amount" => "2500.0",
  #                    "currency_code" => "MAD", "account_id" => "...",
  #                    "payee" => "ext:..." } }
  class Ledger
    def initialize(path)
      @path = path
    end

    def record(client_reference, payment_id:, amount:, currency_code:, account_id:, payee:)
      entry = { "payment_id" => payment_id, "amount" => amount, "currency_code" => currency_code,
                "account_id" => account_id, "payee" => payee }

      # Serialize writers on a separate lock file, write the new ledger to a
      # temporary file and rename it over the old one: a reader sees the old
      # or the new ledger, never a half-written one, and a crash mid-write
      # leaves the old ledger intact.
      File.open("#{@path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        entries = read_entries
        entries[client_reference] = entry
        tmp = "#{@path}.#{Process.pid}.tmp"
        File.write(tmp, JSON.pretty_generate(entries), perm: 0o600)
        File.rename(tmp, @path)
      end
      entry
    end

    # The entry for `client_reference`, or nil.
    def find(client_reference)
      read_entries[client_reference]
    end

    private

    def read_entries
      return {} unless File.exist?(@path)

      json = File.read(@path)
      json.strip.empty? ? {} : JSON.parse(json)
    end
  end
end
