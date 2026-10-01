# frozen_string_literal: true

require "uri"

module Juriscraper
  module Scrapers
    module UnitedStates
      module FederalAppellate
        class CA9Base < OpinionSiteLinear
          def initialize(feed_url:, court_id:, status:, **kwargs)
            super(**kwargs)
            self.court_id = court_id
            self.url = feed_url
            self.status = status
            self.should_have_results = true if kwargs[:content].nil?
          end

          protected

          def make_html_tree(content)
            Nokogiri::XML(content.to_s) { |config| config.recover.nonet }
          end

          def process_html
            seen = {}
            feed_entries.each do |entry|
              link = entry_link(entry)
              name = entry_text(entry, "title")
              date = entry_text(entry, "pubDate", "published", "updated")
              next if link.to_s.empty? || name.to_s.empty? || date.to_s.empty?

              key = [link, name, date]
              next if seen[key]

              seen[key] = true
              cases << {
                name: Utils::StringUtils.titlecase(name),
                url: link,
                date: date,
                status: status,
                docket: docket_from_url(link)
              }
            end
          end

          private

          def feed_entries
            html.xpath("//*[local-name()='item' or local-name()='entry']")
          end

          def entry_text(entry, *names)
            names.each do |name|
              node = entry.at_xpath("./*[local-name()='#{name}']")
              value = node&.text.to_s.strip
              return value unless value.empty?
            end
            nil
          end

          def entry_link(entry)
            node = entry.at_xpath("./*[local-name()='link']")
            return nil unless node

            href = node["href"].to_s.strip
            return href unless href.empty?

            text = node.text.to_s.strip
            text.empty? ? nil : text
          end

          def docket_from_url(value)
            path = URI.parse(value.to_s).path.to_s
            value = File.basename(path, File.extname(path)).to_s.strip
            value.empty? ? nil : value
          rescue URI::InvalidURIError
            nil
          end
        end

        class CA9Published < CA9Base
          FEED_URL = "https://www.ca9.uscourts.gov/decisions/opinions/index.xml"

          def initialize(**kwargs)
            super(feed_url: FEED_URL, court_id: "ca9_p", status: "Published", **kwargs)
          end
        end

        class CA9Unpublished < CA9Base
          FEED_URL = "https://www.ca9.uscourts.gov/decisions/memoranda/index.xml"

          def initialize(**kwargs)
            super(feed_url: FEED_URL, court_id: "ca9_u", status: "Unpublished", **kwargs)
          end
        end
      end
    end
  end
end
