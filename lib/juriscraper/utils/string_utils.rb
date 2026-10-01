# frozen_string_literal: true

module Juriscraper
  module Utils
    module StringUtils
      module_function

      def harmonize(value)
        value.to_s.gsub(/\u00A0/, " ").gsub(/[[:space:]]+/, " ").strip
      end

      def titlecase(value)
        harmonize(value).split(/\s+/).map do |word|
          if word.match?(/\A[A-Z0-9.&'-]{2,}\z/)
            word
          else
            word.split(/([-'])/).map { |part| part.match?(/[-']/) ? part : part.capitalize }.join
          end
        end.join(" ")
      end

      def short_case_name(value)
        text = harmonize(value)
        separator = text.match(/\s+(?:v\.?|vs\.?)\s+/i)
        return text unless separator

        left = text[0...separator.begin(0)]
        right = text[separator.end(0)..]
        "#{short_party(left)} v. #{short_party(right)}"
      end

      def short_party(value)
        harmonize(value)
          .sub(/\A(?:in re|matter of)\s+/i, "")
          .split(/[,;(]/, 2)
          .first
          .to_s
          .strip
      end
    end
  end
end
