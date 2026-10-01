# frozen_string_literal: true

require "date"

module Juriscraper
  module Utils
    module DateUtils
      module_function

      FORMATS = [
        "%Y-%m-%d",
        "%m/%d/%Y",
        "%m/%d/%y",
        "%m-%d-%Y",
        "%B %d, %Y",
        "%b %d, %Y"
      ].freeze

      def parse(value)
        return value if value.is_a?(Date)
        return value.to_date if value.respond_to?(:to_date)

        text = value.to_s.strip
        raise ParsingError, "date is blank" if text.empty?

        FORMATS.each do |format|
          begin
            return Date.strptime(text, format)
          rescue Date::Error
            next
          end
        end

        Date.parse(text)
      rescue Date::Error => e
        raise ParsingError, "unable to parse date #{value.inspect}: #{e.message}"
      end

      def json(value)
        value.respond_to?(:iso8601) ? value.iso8601 : value
      end
    end
  end
end
