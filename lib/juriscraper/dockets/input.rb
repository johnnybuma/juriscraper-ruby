# frozen_string_literal: true

require "json"

module Juriscraper
  module Dockets
    module Input
      module_function

      def read(paths)
        cases = {}
        Array(paths).each do |path|
          payload = JSON.parse(File.read(path, encoding: "bom|utf-8"))
          rows = payload.is_a?(Hash) ? payload["content"] : payload
          raise ConfigurationError, "#{path}: expected a case array or PACER content array" unless rows.is_a?(Array)
          rows.each_with_index do |raw, index|
            raise ConfigurationError, "#{path}: case #{index + 1} must be an object" unless raw.is_a?(Hash)
            identity = Identity.new(raw)
            key = identity.case_id.empty? ? [identity.court, identity.number, Identity.normalize_title(identity.title)] : [identity.court, identity.case_id]
            if cases.key?(key)
              prior = Identity.new(cases[key])
              raise ConfigurationError, "conflicting numbers for court/case ID #{key.join('/')}" unless prior.number_matches?(identity.number)
              raise ConfigurationError, "conflicting titles for court/case ID #{key.join('/')}" unless prior.title_matches?(identity.title)
            else
              cases[key] = raw.merge("source_records" => [])
            end
            cases[key]["source_records"] << { "input_file" => File.expand_path(path), "record_number" => index + 1, "record" => raw }
          end
        end
        cases.values
      rescue JSON::ParserError => e
        raise ConfigurationError, "invalid input JSON: #{e.message}"
      end
    end
  end
end
