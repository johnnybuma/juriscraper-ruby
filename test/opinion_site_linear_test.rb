# frozen_string_literal: true

require_relative "test_helper"

class OpinionSiteLinearTest < Minitest::Test
  class LinearSite < Juriscraper::OpinionSiteLinear
    def initialize
      super(content: "<html></html>")
      self.court_id = "linear"
      self.url = "https://example.test/opinions/"
      self.status = "Published"
    end

    protected

    def process_html
      cases << { name: "Example v. Sample", url: "1.pdf", date: "09/30/2026", docket: "26-1" }
    end
  end

  def test_linear_mapping_and_url_resolution
    row = LinearSite.new.parse.first
    assert_equal "Example v. Sample", row[:case_names]
    assert_equal "https://example.test/opinions/1.pdf", row[:download_urls]
    assert_equal "26-1", row[:docket_numbers]
    assert_equal "Published", row[:precedential_statuses]
  end
end
