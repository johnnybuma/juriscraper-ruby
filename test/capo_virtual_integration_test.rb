# frozen_string_literal: true

require_relative "test_helper"

class CapoVirtualIntegrationTest < Minitest::Test
  FakeSite = Class.new(Juriscraper::OpinionSiteLinear) do
    def initialize(**kwargs)
      super
      self.court_id = "capo_test"
      self.url = "https://example.test/feed"
      self.status = "Published"
    end

    protected

    def process_html
      cases << {
        name: "Alpha v. Beta",
        url: "https://cdn.ca9.uscourts.gov/opinion/alpha.pdf",
        date: "2026-09-30",
        docket: "24-1000"
      }
    end
  end

  FakeLegalAuthority = Class.new do
    class << self
      attr_accessor :calls, :writes

      def scrape_web!(query: nil, seeds: [], profiles: [], **options)
        self.calls ||= []
        calls << { query: query, seeds: seeds, profiles: profiles, options: options }
        self.writes = writes.to_i + 1 unless options[:dry_run]
        ids = options[:dry_run] ? [] : options[:case_law_only] ? [20] : [10]
        if options[:case_law_only]
          { authority_ids: ids, new_authority_ids: ids, visited_urls: ["https://www.courtlistener.com/opinion/20/"], persisted_count: ids.length }
        else
          { authority_ids: ids, new_authority_ids: ids, visited_urls: Array(seeds), persisted_count: ids.length }
        end
      end
    end
  end

  def setup
    Juriscraper.register("capo_test", FakeSite)
    Juriscraper::Integrations::CapoVirtual.configure do |config|
      config.enabled = true
      config.court_ids = ["capo_test"]
      config.max_seed_opinions = 2
    end
    FakeLegalAuthority.calls = []
    FakeLegalAuthority.writes = 0
    Juriscraper::Integrations::CapoVirtual.install!(legal_authority_class: FakeLegalAuthority)
    @integration = Juriscraper::Integrations::CapoVirtual
    @original_discover = @integration.method(:discover)
    @integration.define_singleton_method(:discover) do |**_options|
      [{ court_id: "capo_test", case_name: "Alpha v. Beta", download_url: "https://cdn.ca9.uscourts.gov/opinion/alpha.pdf" }]
    end
  end

  def teardown
    @integration.define_singleton_method(:discover, @original_discover)
  end

  def test_case_law_search_adds_official_court_ingest_and_merges_ids
    result = FakeLegalAuthority.scrape_web!(
      query: "recent Ninth Circuit precedent",
      seeds: [],
      profiles: [],
      sites: [:courtlistener],
      case_law_only: true,
      max_pages: 5,
      min_new_authorities: 2,
      embed_inline: true
    )

    assert_equal 2, FakeLegalAuthority.calls.length
    official_call, primary_call = FakeLegalAuthority.calls
    assert_equal false, official_call.dig(:options, :case_law_only)
    assert_equal [:uscourts], official_call.dig(:options, :sites)
    assert_equal ["https://cdn.ca9.uscourts.gov/opinion/alpha.pdf"], official_call[:seeds]
    assert_equal true, primary_call.dig(:options, :case_law_only)
    assert_equal [10, 20], result[:authority_ids].sort
    assert_equal [10, 20], result[:new_authority_ids].sort
    assert_equal ["capo_test"], result.dig(:juriscraper, :court_ids)
  end

  def test_non_case_law_search_is_untouched
    FakeLegalAuthority.scrape_web!(query: "statute", case_law_only: false)
    assert_equal 1, FakeLegalAuthority.calls.length
  end

  def test_dry_run_supplemental_crawl_cannot_persist_or_embed
    excluded = ["https://cdn.ca9.uscourts.gov/opinion/excluded.pdf"]
    result = FakeLegalAuthority.scrape_web!(
      query: "Alpha", sites: [:courtlistener], case_law_only: true,
      dry_run: true, process_dry_run: true, embed_inline: false, excluded_urls: excluded
    )

    assert_equal 2, FakeLegalAuthority.calls.length
    official_call, primary_call = FakeLegalAuthority.calls
    assert_equal true, official_call.dig(:options, :dry_run)
    assert_equal true, official_call.dig(:options, :process_dry_run)
    assert_equal false, official_call.dig(:options, :embed_inline)
    assert_equal excluded, official_call.dig(:options, :excluded_urls)
    assert_equal true, primary_call.dig(:options, :dry_run)
    assert_equal "Alpha", primary_call[:query]
    assert_equal 0, FakeLegalAuthority.writes
    assert_empty result[:authority_ids]
    assert_equal 0, result[:persisted_count]
  end

  def test_blank_query_does_not_start_supplemental_feed_discovery
    @integration.define_singleton_method(:discover) { |**_options| raise "unexpected feed discovery" }

    FakeLegalAuthority.scrape_web!(query: nil, case_law_only: true)

    assert_equal 1, FakeLegalAuthority.calls.length
  end

  def test_explicit_cde_only_scope_does_not_start_official_court_feed
    @integration.define_singleton_method(:discover) { |**_options| raise "unexpected feed discovery" }

    FakeLegalAuthority.scrape_web!(query: "Alpha", case_law_only: true, cde_only: true)

    assert_equal 1, FakeLegalAuthority.calls.length
  end

  def test_supplemental_pass_honors_explicit_page_cap
    @integration.define_singleton_method(:discover) do |**_options|
      (1..3).map do |number|
        { court_id: "ca9_p", case_name: "Alpha v. Beta #{number}",
          download_url: "https://cdn.ca9.uscourts.gov/opinion/alpha-#{number}.pdf" }
      end
    end

    FakeLegalAuthority.scrape_web!(query: "Alpha", case_law_only: true, max_pages: 1)

    official_call = FakeLegalAuthority.calls.first
    assert_equal 1, official_call[:seeds].length
    assert_equal 1, official_call.dig(:options, :max_pages)
  end

  def test_issue_query_filters_unrelated_official_feed_rows
    rows = [
      { download_urls: "https://cdn.ca9.uscourts.gov/opinion/alpha.pdf", case_names: "Alpha v. Beta",
        docket_numbers: "24-1000", case_dates: Date.new(2026, 9, 30), precedential_statuses: "Published" },
      { download_urls: "https://cdn.ca9.uscourts.gov/opinion/gamma.pdf", case_names: "Coffee v. Delta",
        docket_numbers: "24-2000", case_dates: Date.new(2026, 9, 29), precedential_statuses: "Published" }
    ]
    site = Struct.new(:court_id, :rows) do
      def parse = self
      def map(&block) = rows.map(&block)
    end.new("ca9_p", rows)
    registry = Object.new
    registry.define_singleton_method(:build) { |_court_id| site }
    discovery = @integration::AuthorityDiscovery

    assert_empty discovery.new(query: "fee forfeiture", court_ids: ["ca9_p"], limit: 8, registry: registry).call
    assert_equal ["Alpha v. Beta"], discovery.new(query: "Alpha", court_ids: ["ca9_p"], limit: 8,
      registry: registry).call.map { |row| row[:case_name] }
    assert_equal 2, discovery.new(query: nil, court_ids: ["ca9_p"], limit: 8, registry: registry).call.length
    assert_empty discovery.new(query: "the law", court_ids: ["ca9_p"], limit: 8, registry: registry).call
    assert_empty discovery.new(query: "fee", court_ids: ["ca9_p"], limit: 8, registry: registry).call
  end
end
