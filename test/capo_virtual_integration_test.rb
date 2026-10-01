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
      attr_accessor :calls

      def scrape_web!(query: nil, seeds: [], profiles: [], **options)
        self.calls ||= []
        calls << { query: query, seeds: seeds, profiles: profiles, options: options }
        if options[:case_law_only]
          { authority_ids: [20], new_authority_ids: [20], visited_urls: ["https://www.courtlistener.com/opinion/20/"], persisted_count: 1 }
        else
          { authority_ids: [10], new_authority_ids: [10], visited_urls: Array(seeds), persisted_count: 1 }
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
    Juriscraper::Integrations::CapoVirtual.install!(legal_authority_class: FakeLegalAuthority)
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
end
