# frozen_string_literal: true

module Juriscraper
  module CourtListener
    class Page
      include Enumerable

      attr_reader :count, :next_url, :previous_url, :results, :payload

      def initialize(payload, client:)
        unless payload.is_a?(Hash) && (!payload.key?("results") || payload["results"].is_a?(Array)) &&
               [payload["next"], payload["previous"]].all? { |value| value.nil? || value.is_a?(String) }
          raise CourtListenerError, "invalid CourtListener page"
        end
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

      # Exhaust all cursors unless the caller explicitly requests a page cap.
      def each_result(max_pages: nil, &block)
        return enum_for(:each_result, max_pages: max_pages) unless block_given?
        if !max_pages.nil? && (!max_pages.is_a?(Integer) || max_pages <= 0)
          raise ArgumentError, "max_pages must be nil or a positive integer"
        end

        page = self
        pages = 0
        visited = {}
        while page
          page.each(&block)
          pages += 1
          break if max_pages && pages >= max_pages
          break if page.next_url.to_s.empty?
          raise CourtListenerError, "repeated CourtListener pagination URL" if visited[page.next_url]
          visited[page.next_url] = true
          page = page.next_page
          raise CourtListenerError, "invalid CourtListener pagination response" unless page.is_a?(Page)
        end
      end
    end
  end
end
