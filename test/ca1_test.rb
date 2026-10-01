# frozen_string_literal: true

require_relative "test_helper"

class CA1Test < Minitest::Test
  def test_fixture
    html = File.binread(File.join(__dir__, "fixtures", "ca1.html"))
    site = Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA1.new(content: html).parse

    assert_equal 2, site.size
    assert_equal "Smith v. Jones", site[0][:case_names]
    assert_equal "Published", site[0][:precedential_statuses]
    assert_equal "24-1234", site[0][:docket_numbers]
    assert_equal "District of Massachusetts", site[0][:lower_courts]
    assert_equal "https://www.ca1.uscourts.gov/opn/pdfs/24-1234P-01A.pdf", site[0][:download_urls]
  end
end
