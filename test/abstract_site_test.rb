# frozen_string_literal: true

require_relative "test_helper"

class AbstractSiteTest < Minitest::Test
  class FakeSite < Juriscraper::OpinionSite
    def initialize
      super(content: "<html></html>")
      self.court_id = "fake"
      self.url = "https://example.test/"
    end

    protected

    def get_case_dates = [Date.new(2026, 1, 1), Date.new(2026, 2, 1)]
    def get_case_names = ["Alpha v. Beta", "Gamma v. Delta"]
    def get_download_urls = ["https://example.test/a.pdf", "https://example.test/b.pdf"]
    def get_precedential_statuses = ["Published", "Unpublished"]
  end

  def test_parse_sorts_newest_first_and_is_enumerable
    site = FakeSite.new.parse
    assert_equal ["Gamma v. Delta", "Alpha v. Beta"], site.map { |row| row[:case_names] }
    assert_equal Date.new(2026, 2, 1), site[0][:case_dates]
    assert_equal false, site[0][:blocked_statuses]
    assert_match(/\A[0-9a-f]{40}\z/, site.snapshot_hash)
  end

  def test_json_uses_iso_dates
    json = JSON.parse(FakeSite.new.parse.to_json)
    assert_equal "2026-02-01", json[0]["case_dates"]
  end
end
