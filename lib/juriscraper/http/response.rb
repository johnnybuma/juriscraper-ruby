# frozen_string_literal: true

module Juriscraper
  module HTTP
    Response = Struct.new(:status, :headers, :body, :url, keyword_init: true) do
      def content_type
        headers["content-type"]&.split(";", 2)&.first&.strip&.downcase
      end

      def success?
        status.between?(200, 299)
      end
    end
  end
end
