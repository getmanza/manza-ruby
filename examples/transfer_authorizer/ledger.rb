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

      File.open(@path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        entries = parse(file.read)
        entries[client_reference] = entry
        file.rewind
        file.write(JSON.pretty_generate(entries))
        file.flush
        file.truncate(file.pos)
      end
      entry
    end

    # The entry for `client_reference`, or nil.
    def find(client_reference)
      return nil unless File.exist?(@path)

      File.open(@path) do |file|
        file.flock(File::LOCK_SH)
        parse(file.read)[client_reference]
      end
    end

    private

    def parse(json)
      json.to_s.strip.empty? ? {} : JSON.parse(json)
    end
  end
end
