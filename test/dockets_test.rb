# frozen_string_literal: true

require_relative "test_helper"
require "tmpdir"
require "stringio"

class DocketsTest < Minitest::Test
  RECORD = { "caseId" => 867593, "courtId" => "candc", "caseNumberFull" => "3:2026cv04737", "caseTitle" => "Alpha v. U.S. et al." }.freeze
  CANDIDATE = { "id" => 10, "pacer_case_id" => "867593", "court_id" => "cand", "docket_number" => "3:26-cv-04737-JD", "case_name" => "Alpha v. United States" }.freeze

  class FakeHTTP
    attr_reader :calls
    def initialize(&handler)
      @handler, @calls = handler, []
    end
    def request(method, path, **options)
      @calls << [method, path, options]
      @handler.call(method, path, options)
    end
  end

  def page(results, next_url: nil)
    { "results" => results, "next" => next_url }
  end

  def test_scans_all_pages_and_selects_only_verified_identity
    http = FakeHTTP.new do |_method, path, _options|
      if path == "dockets"
        page([CANDIDATE.merge("court_id" => "nysd")], next_url: "page2")
      elsif path == "page5"
        page([CANDIDATE])
      else
        number = path.delete_prefix("page").to_i
        page([CANDIDATE.merge("id" => number + 10, "case_name" => "Unrelated")], next_url: "page#{number + 1}")
      end
    end
    client = Juriscraper::CourtListener::Client.new(http: http)
    assert_equal 10, client.find_docket(RECORD)["id"]
    assert_equal 5, http.calls.length
    assert_equal "867593", http.calls.first[2][:params][:pacer_case_id]
  end

  def test_rejects_every_conflicting_identity_field
    %w[court_id pacer_case_id docket_number case_name].zip(%w[nysd 333 3:2026cv88888 Unrelated]).each do |field, value|
      http = FakeHTTP.new { page([CANDIDATE.merge(field => value)]) }
      error = assert_raises(Juriscraper::DocketNotFoundError) { Juriscraper::CourtListener::Client.new(http: http).find_docket(RECORD) }
      assert_equal 1, error.candidates.length
    end
  end

  def test_ambiguous_verified_candidates_are_never_selected
    http = FakeHTTP.new { page([CANDIDATE, CANDIDATE.merge("id" => 11)]) }
    assert_raises(Juriscraper::AmbiguousDocketError) { Juriscraper::CourtListener::Client.new(http: http).find_docket(RECORD) }
  end

  def test_complete_entries_exclude_documents_and_verify_count
    entries = (1..5).map { |i| { "id" => i, "docket" => "https://www.courtlistener.com/api/rest/v4/dockets/10/", "entry_number" => nil,
      "date_filed" => nil, "description" => "entry #{i}", "recap_documents" => [{ "plain_text" => "filing" }] } }
    http = FakeHTTP.new do |_method, path, options|
      if path == "dockets"
        page([CANDIDATE])
      elsif options.dig(:params, :count) == "on"
        { "count" => 5 }
      else
        i = path == "docket-entries" ? 1 : path.delete_prefix("entrypage").to_i
        page([entries[i - 1]], next_url: i < 5 ? "entrypage#{i + 1}" : nil)
      end
    end
    result = Juriscraper::CourtListener::Client.new(http: http).docket_report(RECORD)
    assert_equal 5, result["entry_count"]
    assert_nil result["docket_entries"].first["entry_number"]
    refute result["docket_entries"].any? { |entry| entry.key?("recap_documents") }
    assert_equal "recap_documents", http.calls[1][2][:params][:omit]
    assert result["api_count_verified"]
  end

  def test_count_mismatch_and_wrong_docket_are_errors
    ["count", "docket"].each do |failure|
      http = FakeHTTP.new do |_method, path, options|
        if path == "dockets"
          page([CANDIDATE])
        elsif options.dig(:params, :count)
          { "count" => 2 }
        else
          page([{ "id" => 1, "docket" => failure == "docket" ? 99 : 10, "description" => "one", "date_filed" => nil, "entry_number" => 1 }])
        end
      end
      assert_raises(Juriscraper::CourtListenerError) { Juriscraper::CourtListener::Client.new(http: http).docket_report(RECORD) }
    end
  end

  def test_repeated_cursor_fails_and_explicit_cap_does_not_fetch_extra_page
    http = FakeHTTP.new { page([CANDIDATE], next_url: "repeat") }
    client = Juriscraper::CourtListener::Client.new(http: http)
    first = client.dockets
    assert_equal [CANDIDATE], first.each_result(max_pages: 1).to_a
    assert_equal 1, http.calls.length
    assert_raises(Juriscraper::CourtListenerError) { first.each_result.to_a }
  end

  def fake_provider(result: nil, error: nil)
    Object.new.tap do |client|
      client.define_singleton_method(:docket_report) { |_record| raise error if error; result }
    end
  end

  def test_fallback_only_for_no_results_and_both_keep_reports_separate
    report = { "docket_entries" => [{ "description" => "entry" }] }
    missing = fake_provider(error: Juriscraper::DocketNotFoundError.new("none"))
    found = fake_provider(result: report)
    result = Juriscraper::Dockets::Fetcher.new(pacer: found, courtlistener: missing).fetch(RECORD, source: :courtlistener)
    assert_equal "pacer", result["fallback_source"]
    assert_equal "complete", result["status"]
    empty = fake_provider(result: { "docket_entries" => [] })
    assert_equal "courtlistener", Juriscraper::Dockets::Fetcher.new(pacer: empty, courtlistener: found).fetch(RECORD, source: :pacer)["fallback_source"]
    result = Juriscraper::Dockets::Fetcher.new(pacer: found, courtlistener: found).fetch(RECORD, source: :both)
    assert_equal %w[pacer courtlistener], result["sources"].keys
    assert_nil result["fallback_source"]
    [Juriscraper::AmbiguousDocketError, Juriscraper::CourtListenerAuthError, Juriscraper::ParsingError].each do |klass|
      broken = fake_provider(error: klass.new("failed"))
      assert_raises(klass) { Juriscraper::Dockets::Fetcher.new(pacer: found, courtlistener: broken).fetch(RECORD) }
    end
  end

  def test_both_attempts_each_source_and_resume_reuses_completed_report
    found = fake_provider(result: { "docket_entries" => [{ "description" => "one" }] })
    broken = fake_provider(error: Juriscraper::PacerAuthError.new("bad login"))
    result = Juriscraper::Dockets::Fetcher.new(pacer: broken, courtlistener: found).fetch(RECORD, source: :both)
    assert_equal "partial", result["status"]
    assert_equal "error", result["sources"]["pacer"]["status"]
    assert_equal "complete", result["sources"]["courtlistener"]["status"]
    no_requery = fake_provider(error: RuntimeError.new("completed source queried twice"))
    retried = Juriscraper::Dockets::Fetcher.new(pacer: found, courtlistener: no_requery).fetch(RECORD, source: :both, previous: result)
    assert_equal "complete", retried["status"]
  end

  def test_input_deduplicates_cases_and_preserves_source_rows
    Dir.mktmpdir do |dir|
      path = File.join(dir, "input.json")
      File.write(path, JSON.generate("content" => [RECORD.merge("attorney" => "A"), RECORD.merge("attorney" => "B")]))
      cases = Juriscraper::Dockets::Input.read([path])
      assert_equal 1, cases.length
      assert_equal %w[A B], cases.first["source_records"].map { |row| row["record"]["attorney"] }
    end
  end

  def test_identity_handles_court_aliases_and_rejects_malicious_urls
    identity = Juriscraper::Dockets::Identity.new(RECORD)
    assert identity.number_matches?("3:26-cv-04737-JD")
    refute identity.number_matches?("3:2025-cv-04737")
    refute identity.number_matches?("1:2026cv04737")
    assert identity.title_matches?("Alpha vs. United States")
    assert_equal ["cand", "867593"], identity.pacer_target
    assert_raises(Juriscraper::ConfigurationError) do
      Juriscraper::Dockets::Identity.new(RECORD.merge("caseUrl" => "https://ecf.nysd.uscourts.gov/cgi-bin/iqquerymenu.pl?867593")).pacer_target
    end
  end
end
