# frozen_string_literal: true

module Manza
  # A single page of a list endpoint's response.
  #
  # The Manza API uses cursor pagination. Every list endpoint returns
  # `{data: [...], has_more: bool, next_cursor: string|null}`. This
  # class wraps that shape and exposes a cursor-walking helper.
  #
  # Pages are intentionally not auto-paginating. The SDK refuses to
  # let callers iterate every record across many pages with a single
  # call — that's the failure mode that caused unbounded fetches in
  # the CLI's `--all` flag. Callers walk pages explicitly:
  #
  #   page = client.invoices.list(limit: 100)
  #   while page
  #     page.data.each { |inv| ... }
  #     page = page.next
  #   end
  #
  # Or with a max-items cap that the caller can reason about:
  #
  #   client.invoices.each_page(max_items: 500) { |inv| ... }
  class Page
    # Hard ceiling on per-page size. Server enforces this too; we
    # refuse to send a larger value rather than silently get clamped.
    MAX_PER_PAGE = 100

    attr_reader :response, :data, :has_more, :next_cursor

    def initialize(response, fetcher:)
      @response = response
      @fetcher = fetcher

      body = response.body
      unless body.is_a?(Hash) && body["data"].is_a?(Array)
        raise Manza::Error.new("List response missing 'data' array",
                               body:)
      end

      @data = body["data"]
      @has_more = body.fetch("has_more", false)
      @next_cursor = body["next_cursor"]
    end

    def request_id
      response.request_id
    end

    # Fetches the next page. Returns nil when there are no more pages.
    def next
      return nil unless has_more && next_cursor

      @fetcher.call(next_cursor)
    end

    def each(&)
      data.each(&)
    end

    include Enumerable

    def inspect
      "#<#{self.class.name} count=#{data.size} has_more=#{has_more} next_cursor=#{next_cursor.inspect}>"
    end
  end
end
