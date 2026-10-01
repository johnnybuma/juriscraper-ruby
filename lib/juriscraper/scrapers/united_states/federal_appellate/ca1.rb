# frozen_string_literal: true

module Juriscraper
  module Scrapers
    module UnitedStates
      module FederalAppellate
        class CA1 < OpinionSiteLinear
          BASE_URL = "https://www.ca1.uscourts.gov/opn/aci"

          def initialize(**kwargs)
            super
            self.court_id = "ca1"
            self.url = BASE_URL
            self.should_have_results = true if kwargs[:content].nil?
          end

          protected

          def process_html
            html.xpath("//tr[not(th)]").each do |row|
              title_node = row.at_xpath("td[2]/a")
              docket_node = row.at_xpath("td[3]/a")
              date_node = row.at_xpath("td[1]/span")
              name_node = row.xpath("td[4]/text()").find { |node| !node.text.strip.empty? }
              next unless title_node && docket_node && date_node && name_node

              cases << {
                name: name_node.text,
                url: title_node["href"],
                date: date_node.text,
                status: status_from_title(title_node.text),
                docket: docket_node.text,
                lower_court: row.at_xpath("td[4]/span")&.text
              }
            end
          end

          private

          def status_from_title(title)
            value = title.to_s
            return "Unpublished" if value.include?("U")
            return "Published" if value.include?("P")
            return "Errata" if value.include?("E")

            "Unknown"
          end
        end
      end
    end
  end
end
