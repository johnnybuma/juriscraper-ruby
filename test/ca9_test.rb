# frozen_string_literal: true

require_relative "test_helper"

class CA9Test < Minitest::Test
  def test_published_feed
    html = File.binread(File.join(__dir__, "fixtures", "ca9.xml"))
    site = Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA9Published.new(content: html).parse

    assert_equal 2, site.size
    assert_equal "Smith V. Jones", site[0][:case_names]
    assert_equal "24-1234", site[0][:docket_numbers]
    assert_equal "Published", site[0][:precedential_statuses]
    assert_equal "https://cdn.ca9.uscourts.gov/datastore/opinions/2026/09/30/24-1234.pdf", site[0][:download_urls]
  end

  def test_unpublished_feed_reuses_parser
    html = File.binread(File.join(__dir__, "fixtures", "ca9.xml"))
    site = Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA9Unpublished.new(content: html).parse

    assert_equal "Unpublished", site[0][:precedential_statuses]
  end
end
