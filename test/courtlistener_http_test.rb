# frozen_string_literal: true

require_relative "test_helper"

class CourtListenerHTTPTest < Minitest::Test
  def transport
    Juriscraper::CourtListener::Http.new(base: "https://www.courtlistener.com/api/rest/v4", token: "test-secret",
      open_timeout: 5, read_timeout: 10, user_agent: "test")
  end

  def test_rejects_cross_origin_redirect_without_resending_post_body
    http = transport
    calls = []
    http.define_singleton_method(:transmit) do |_method, uri, **_options|
      calls << uri.to_s
      Net::HTTPFound.new("1.1", "302", "Found").tap { |response| response["location"] = "https://example.com/capture" }
    end
    assert_raises(Juriscraper::CourtListenerError) { http.request(:post, "recap-fetch", body: { pacer_password: "password" }) }
    assert_equal 1, calls.length
    assert_raises(Juriscraper::CourtListenerError) { http.build_uri("https://www.courtlistener.com:444/api/rest/v4/dockets/") }
  end

  def test_token_header_and_error_redaction
    http = transport
    request = http.build_request(:get, http.build_uri("dockets", pacer_case_id: 123))
    assert_equal "Token test-secret", request["Authorization"]
    error = assert_raises(Juriscraper::CourtListenerAuthError) { http.interpret(status: 401, body: JSON.generate("detail" => "bad token test-secret")) }
    refute_includes error.message, "test-secret"
    refute_includes http.inspect, "test-secret"
  end

  def test_environment_key_alias_and_explicit_blank_override
    old_token, old_key = ENV["COURTLISTENER_TOKEN"], ENV["COURTLISTENER_API_KEY"]
    ENV["COURTLISTENER_TOKEN"], ENV["COURTLISTENER_API_KEY"] = "", "alias-key"
    config = Juriscraper::Configuration.new
    assert_equal "alias-key", config.resolved_courtlistener_token
    config.courtlistener_token = ""
    assert_equal "", config.resolved_courtlistener_token
    refute_includes config.inspect, "alias-key"
  ensure
    ENV["COURTLISTENER_TOKEN"], ENV["COURTLISTENER_API_KEY"] = old_token, old_key
  end
end
