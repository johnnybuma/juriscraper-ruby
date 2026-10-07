# frozen_string_literal: true

module Juriscraper
  module CourtListener
    class Page
      include Enumerable

      attr_reader :count, :next_url, :previous_url, :results, :payload

      def initialize(payload, client:)
        @payload = payload.is_a?(Hash) ? payload : {}
        @count = @payload["count"]
        @next_url = @payload["next"]
        @previous_url = @payload["previous"]
        @results = Array(@payload["results"])
        @client = client
      end

      def each(&block)
        return enum_for(:each) unless block_given?

        results.each(&block)
      end

      def next_page
        return nil if next_url.to_s.empty?

        @client.get_url(next_url)
      end

      # Walks cursors. Capped so a scrape cannot silently burn the daily quota.
      def each_result(max_pages: 3, &block)
        return enum_for(:each_result, max_pages: max_pages) unless block_given?

        page = self
        pages = 0
        while page && pages < max_pages
          page.each(&block)
          pages += 1
          page = page.next_page
        end
      end
    end
  end
end
