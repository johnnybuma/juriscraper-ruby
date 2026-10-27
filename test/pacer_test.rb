# frozen_string_literal: true

require_relative "test_helper"

class PacerTest < Minitest::Test
  RECORD = { "caseId" => 123, "courtId" => "candc", "caseNumberFull" => "3:2026cv00001", "caseTitle" => "Alpha v. Beta" }.freeze
  HTML = <<~HTML.freeze
    <html><body><h3>DOCKET FOR CASE #: 3:26-cv-00001-JD</h3>
    <table><tr><td>Alpha v. Beta<br>Assigned to: Judge Example</td></tr></table>
    <table><tr><th>Date Filed</th><th>#</th><th>Docket Text</th></tr>
    <tr><td>10/01/2026</td><td><a href="/doc1/123">1</a></td><td>Complaint.<br>(Entered: 10/02/2026)</td></tr>
    <tr><td></td><td>1</td><td>Unnumbered date text</td></tr></table>
    <table><tr><td>10/03/2026</td><td></td><td>Minute entry.</td></tr></table>
    <table><tr><td>PACER Service Center Transaction Receipt</td></tr></table></body></html>
  HTML

  class FakeHTTP
    attr_reader :calls
    def initialize(*responses)
      @responses, @calls = responses, []
    end
    def request(method, url, **options)
      @calls << [method, url, options]
      raise "unexpected network request: #{url}" if @responses.empty?
      status, body, headers = @responses.shift
      Juriscraper::HTTP::Response.new(status: status, body: body.is_a?(String) ? body : JSON.generate(body), headers: headers || {}, url: url)
    end
  end

  def auth(token = "session-secret")
    [200, { "loginResult" => "0", "nextGenCSO" => token }]
  end

  def client(http, **options)
    Juriscraper::Pacer::Client.new(username: "example-user", password: "example-password", client_code: "test-client", http: http, **options)
  end

  def test_authentication_mfa_token_rotation_and_logout
    http = FakeHTTP.new(auth, [200, HTML, { "x-next-gen-cso" => "rotated-secret" }], [200, { "loginResult" => "0" }])
    session = client(http, otp_provider: -> { "123456" })
    report = session.docket_report(RECORD)
    assert_equal 3, report["entry_count"]
    assert_equal "123456", http.calls[0][2][:json]["otpCode"]
    assert_equal "example-user", http.calls[0][2][:json]["loginId"]
    assert_equal "test-client", http.calls[0][2][:json]["clientCode"]
    assert_equal "session-secret", http.calls[1][2][:token]
    assert_equal "", http.calls[1][2][:form]["date_from"]
    session.logout
    assert_equal "rotated-secret", http.calls[2][2][:json]["nextGenCSO"]
    refute session.authenticated?
    refute_includes session.inspect, "example-password"
    refute http.calls.any? { |_method, url, _options| url.include?("doc1") }
  end

  def test_pcl_pagination_and_compact_case_number
    wrong = RECORD.merge("caseId" => 999, "caseTitle" => "Other")
    page = ->(items, number, last) { { "content" => items, "pageInfo" => { "number" => number, "numberOfElements" => items.length, "last" => last, "totalElements" => 2 } } }
    http = FakeHTTP.new(auth, [200, page.call([wrong], 0, false)], [200, page.call([RECORD], 1, true)])
    record = RECORD.reject { |key, _| key == "caseId" }
    assert_equal 123, client(http).find_case(record)["caseId"]
    assert_equal({ "caseNumberFull" => "3:2026cv00001" }, http.calls[1][2][:json])
    assert http.calls[2][1].end_with?("?page=1")
  end

  def test_406_retains_validation_details_and_redacts_credentials_and_used_otp
    http = FakeHTTP.new(auth, [406, "bad caseNumberFull example-password session-secret 654321"])
    session = client(http, otp: "654321")
    error = assert_raises(Juriscraper::PacerError) { session.search_cases("caseNumberFull" => "bad") }
    assert_includes error.message, "caseNumberFull"
    %w[example-password session-secret 654321].each { |secret| refute_includes error.message, secret }
    assert_equal 2, http.calls.length
  end

  def test_mfa_rejection_does_not_leak_generated_otp
    http = FakeHTTP.new([200, { "loginResult" => "1", "errorDescription" => "wrong code 987654" }])
    error = assert_raises(Juriscraper::PacerAuthError) { client(http, otp_provider: -> { "987654" }).authenticate! }
    refute_includes error.message, "987654"
  end

  def test_invalid_pcl_pagination_and_rate_limits_are_not_empty_results
    http = FakeHTTP.new(auth, [200, { "content" => [], "pageInfo" => {} }])
    assert_raises(Juriscraper::PacerError) { client(http).search_cases({}) }
    http = FakeHTTP.new(auth, [429, "limit", { "retry-after" => "60" }])
    error = assert_raises(Juriscraper::PacerRateLimitError) { client(http).search_cases({}) }
    assert_equal "60", error.retry_after
  end

  def test_report_preserves_blank_dates_duplicate_and_missing_entry_numbers
    report = Juriscraper::Pacer::DocketReport.new.parse(HTML, identity: Juriscraper::Dockets::Identity.new(RECORD))
    entries = report["docket_entries"]
    assert_equal [1, 1, nil], entries.map { |entry| entry["entry_number"] }
    assert_equal ["2026-10-01", nil, "2026-10-03"], entries.map { |entry| entry["date_filed"] }
    assert_equal "2026-10-02", entries[0]["date_entered"]
    assert_includes entries[0]["description"], "\n"
    assert report["metadata"]["case_name_verified"]
    [HTML.sub("3:26-cv-00001-JD", "3:26-cv-99999-JD"), HTML.sub("Alpha v. Beta", "Other v. Person"), "<html>unexpected</html>"].each do |html|
      assert_raises(Juriscraper::ParsingError) { Juriscraper::Pacer::DocketReport.new.parse(html, identity: Juriscraper::Dockets::Identity.new(RECORD)) }
    end
  end

  def test_two_digit_and_invalid_dates_preserve_raw_text
    html = HTML.sub("10/01/2026", "10/01/26").sub("10/03/2026", "unknown date")
    entries = Juriscraper::Pacer::DocketReport.new.parse(html, identity: Juriscraper::Dockets::Identity.new(RECORD))["docket_entries"]
    assert_equal "2026-10-01", entries[0]["date_filed"]
    assert_nil entries[2]["date_filed"]
    assert_equal "unknown date", entries[2]["date_filed_text"]
  end

  def test_bankruptcy_extra_column_and_untyped_header
    html = HTML.sub("DOCKET FOR CASE #: 3:26-cv-00001-JD", "Bankruptcy Petition #: 26-00001").sub("<td><a", "<td>info</td><td><a")
    record = RECORD.merge("courtId" => "akbk", "caseNumberFull" => "3:2026bk00001")
    assert_equal 3, Juriscraper::Pacer::DocketReport.new.parse(html, identity: Juriscraper::Dockets::Identity.new(record))["entry_count"]
  end

  def test_multiline_title_and_multi_document_layout_preserve_minute_entries
    html = HTML.sub("Alpha v. Beta<br>", "Alpha v.\n Beta<br>")
    html = html.sub("<th>Docket Text</th>", "<th>Select all / clear</th><th>Docket Text</th>")
    html = html.sub("<td>Complaint.", '<td><input name="all_documents"></td><td>Complaint.')
    html = html.sub("<td>Unnumbered date text", "<td></td><td>Unnumbered date text")
    html = html.sub("</body>", "<table><tr><td></td><td></td><td>Total filesize of selected documents (MB): 0</td></tr></table></body>")
    result = Juriscraper::Pacer::DocketReport.new.parse(html, identity: Juriscraper::Dockets::Identity.new(RECORD))
    assert_equal 3, result["entry_count"]
    assert_equal "Unnumbered date text", result["docket_entries"][1]["description"]
  end

  def test_large_report_confirmation_is_same_court_and_never_fetches_documents
    confirmation = '<p>This report may take a long time</p><form action="/cgi-bin/DktRpt.pl?confirmed"><input name="all_case_ids" value="123"></form>'
    http = FakeHTTP.new(auth, [200, confirmation], [200, HTML])
    assert_equal 3, client(http).docket_report(RECORD)["entry_count"]
    assert_equal({ "all_case_ids" => "123" }, http.calls[2][2][:form])
    http = FakeHTTP.new(auth, [200, confirmation.sub('/cgi-bin/DktRpt.pl?confirmed', 'https://example.com/cgi-bin/DktRpt.pl')])
    assert_raises(Juriscraper::PacerError) { client(http).docket_report(RECORD) }
    assert_equal 2, http.calls.length
  end

  def test_totp_rfc6238_vectors
    secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ"
    assert_equal "287082", Juriscraper::Pacer::TOTP.code(secret, time: 59)
    assert_equal "081804", Juriscraper::Pacer::TOTP.code(secret, time: 1_111_111_109)
    assert_raises(Juriscraper::ConfigurationError) { Juriscraper::Pacer::TOTP.code("invalid!") }
  end

  def test_transport_headers_and_restricted_endpoints
    transport = Juriscraper::Pacer::Http.new
    captured = []
    transport.define_singleton_method(:transmit) do |_uri, request|
      captured << request
      Net::HTTPOK.new("1.1", "200", "OK").tap do |response|
        response.instance_variable_set(:@read, true)
        response.body = "{}"
      end
    end
    transport.request(:post, Juriscraper::Pacer::Client::PCL_URL, json: { "caseNumberFull" => "3:2026cv00001" }, token: "secret")
    assert_equal "application/json", captured[0]["Content-Type"]
    assert_equal "application/json", captured[0]["Accept"]
    assert_equal "secret", captured[0]["X-NEXT-GEN-CSO"]
    transport.request(:post, "https://ecf.cand.uscourts.gov/cgi-bin/DktRpt.pl", form: { "all_case_ids" => "123" }, token: "secret")
    assert_includes captured[1]["Cookie"], "NextGenCSO=secret"
    ["https://example.com/", "http://pcl.uscourts.gov/pcl-public-api/rest/cases/find", "https://ecf.cand.uscourts.gov/doc1/123", "https://ecf.cand.uscourts.gov:444/cgi-bin/DktRpt.pl"].each do |url|
      assert_raises(Juriscraper::PacerError) { transport.request(:post, url) }
    end
  end
end
