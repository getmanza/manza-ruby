# frozen_string_literal: true

module Manza
  module Resources
    # Shared scaffolding for every resource module. Carries a back-
    # reference to the client and exposes thin HTTP helpers that
    # delegate to {Manza::Client#request}.
    #
    # Note on naming: the helpers are `http_get`, `http_post`, etc.
    # rather than `get`/`post` so they do not shadow the public
    # methods on resource subclasses. Public resources commonly
    # define a `get(id)` method, and a same-named private helper on
    # the base class would let `Base#list_page` accidentally dispatch
    # to the subclass version when a list endpoint is hit.
    #
    # Pagination:
    #
    #   Every resource that has a list endpoint exposes `#list` which
    #   returns a {Manza::Page}. Callers can walk pages explicitly via
    #   `page.next` or use `each_page_record` for capped iteration.
    class Base
      MAX_PER_PAGE = Page::MAX_PER_PAGE

      attr_reader :client

      def initialize(client)
        @client = client
      end

      private

      def http_get(path, params: nil)
        client.request(:get, path, params: params)
      end

      def http_post(path, body: nil)
        client.request(:post, path, body: body)
      end

      def http_patch(path, body: nil)
        client.request(:patch, path, body: body)
      end

      def http_delete(path)
        client.request(:delete, path)
      end

      # Builds a paginated list. `path` is the collection endpoint;
      # `params` is everything else (filters, etc.). `limit` is enforced
      # at MAX_PER_PAGE; the caller can pass `cursor:` to fetch a
      # specific page.
      def list_page(path, limit: MAX_PER_PAGE, cursor: nil, **params)
        validated_limit = validate_limit!(limit)

        fetcher = lambda { |next_cursor|
          query = params.merge(limit: validated_limit, cursor: next_cursor).compact
          response = http_get(path, params: query)
          Page.new(response, fetcher: fetcher)
        }

        initial_query = params.merge(limit: validated_limit, cursor: cursor).compact
        response = http_get(path, params: initial_query)
        Page.new(response, fetcher: fetcher)
      end

      # Iterates list-endpoint records up to `max_items`, fetching
      # additional pages on demand. Caps ensure callers never
      # accidentally pull a full table.
      #
      # Pass either a block or get an Enumerator back.
      def each_page_record(path, max_items:, **params, &block)
        return enum_for(:each_page_record, path, max_items: max_items, **params) unless block

        unless max_items.is_a?(Integer) && max_items.positive?
          raise ArgumentError,
                "max_items must be a positive integer"
        end

        seen = 0
        page = list_page(path, **params)

        loop do
          page.data.each do |record|
            return seen if seen >= max_items

            yield record
            seen += 1
          end

          break unless page.has_more && seen < max_items

          page = page.next
          break if page.nil?
        end

        seen
      end

      def validate_limit!(limit)
        return MAX_PER_PAGE if limit.nil?

        raise Manza::ArgumentError, "limit must be a positive integer (got #{limit.inspect})" unless limit.is_a?(Integer) && limit.positive?

        raise Manza::ArgumentError, "limit cannot exceed #{MAX_PER_PAGE} (got #{limit})" if limit > MAX_PER_PAGE

        limit
      end

      # Builds a request path by joining a literal base path with one
      # or more dynamic segments. The base is appended verbatim; each
      # dynamic segment is percent-encoded so an ID containing `/` or
      # other special characters cannot escape the intended path.
      #
      #   encode_path('api/accounts', 'acc_xyz')
      #     # => "api/accounts/acc_xyz"
      #
      #   encode_path('api/accounts', 'acc 1', 'transactions', 'tx 1')
      #     # => "api/accounts/acc%201/transactions/tx%201"
      def encode_path(base, *segments)
        encoded_segments = segments.map do |s|
          str = s.to_s
          # An empty segment would silently turn `/things/:id` into
          # `/things/`, which on most APIs redispatches to the list
          # endpoint and returns a Page-shaped body. Surface it loudly.
          raise Manza::ArgumentError, "path segment cannot be blank" if str.empty?

          # CGI.escape replaces ' ' with '+', which is wrong for path
          # segments. Use a manual escape that targets only characters
          # that would change path semantics.
          str.gsub(/[^A-Za-z0-9._~-]/) { |c| format("%%%02X", c.ord) }
        end
        ([base] + encoded_segments).join("/")
      end
    end
  end
end
