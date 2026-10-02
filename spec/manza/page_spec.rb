# frozen_string_literal: true

require "spec_helper"

RSpec.describe Manza::Page do
  let(:noop_fetcher) { ->(_cursor) { raise "not called" } }

  def faraday_response(body)
    instance_double(
      Faraday::Response,
      body: body,
      status: 200,
      headers: { "x-request-id" => "req_test" }
    )
  end

  it "exposes data, has_more, next_cursor" do
    body = { "data" => [{ "id" => "a" }, { "id" => "b" }], "has_more" => true, "next_cursor" => "cur_2" }
    response = Manza::Response.new(faraday_response(body))
    page = described_class.new(response, fetcher: noop_fetcher)
    expect(page.data).to eq([{ "id" => "a" }, { "id" => "b" }])
    expect(page.has_more).to be true
    expect(page.next_cursor).to eq("cur_2")
  end

  it "raises when body has no data array" do
    response = Manza::Response.new(faraday_response({ "items" => [] }))
    expect { described_class.new(response, fetcher: noop_fetcher) }
      .to raise_error(Manza::Error, /missing 'data' array/)
  end

  it "returns nil from #next when has_more is false" do
    body = { "data" => [], "has_more" => false, "next_cursor" => nil }
    response = Manza::Response.new(faraday_response(body))
    page = described_class.new(response, fetcher: noop_fetcher)
    expect(page.next).to be_nil
  end

  it "calls fetcher with next_cursor when has_more" do
    body = { "data" => [{ "id" => "a" }], "has_more" => true, "next_cursor" => "cur_2" }
    response = Manza::Response.new(faraday_response(body))
    fetcher = ->(cursor) { [:fetched, cursor] }
    page = described_class.new(response, fetcher: fetcher)
    expect(page.next).to eq([:fetched, "cur_2"])
  end

  it "is enumerable" do
    body = { "data" => [{ "id" => "a" }, { "id" => "b" }], "has_more" => false, "next_cursor" => nil }
    response = Manza::Response.new(faraday_response(body))
    page = described_class.new(response, fetcher: noop_fetcher)
    expect(page.map { |r| r["id"] }).to eq(%w[a b])
  end
end
