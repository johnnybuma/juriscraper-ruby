# frozen_string_literal: true

require "uri"

module Juriscraper
  module Dockets
    # Canonical identity shared by the PACER and CourtListener providers.
    # PACER case IDs are only meaningful together with their source court.
    class Identity
      attr_reader :record, :case_id, :number, :title, :court

      def initialize(record = {}, **overrides)
        @record = record.to_h.transform_keys(&:to_s).merge(overrides.transform_keys(&:to_s).reject { |_k, v| v.nil? })
        @case_id = first("pacer_case_id", "caseId", "case_id").to_s
        @case_id = Integer(@case_id).to_s unless @case_id.empty?
        raise ConfigurationError, "PACER case ID must be positive" if !@case_id.empty? && @case_id.to_i <= 0

        @number = first("docket_number", "caseNumberFull", "Number").to_s.strip
        @title = first("case_name", "caseTitle", "Case").to_s.strip
        @court = self.class.normalize_court(first("court", "courtId", "pacer_court_id"))
        raise ConfigurationError, "case number and case title are required" if @number.empty? || @title.empty?
      rescue ArgumentError, TypeError
        raise ConfigurationError, "PACER case ID must be a positive integer"
      end

      def first(*keys)
        keys.each { |key| return record[key] unless record[key].nil? || record[key].to_s.empty? }
        nil
      end

      def self.normalize_court(value)
        value = value["id"] || value[:id] if value.is_a?(Hash)
        code = value.to_s.downcase.sub(%r{/$}, "").split("/").last.to_s
        code = code[0...-1] if code.end_with?("dc", "bk")
        { "azb" => "arb", "neb" => "nebraskab", "cofc" => "uscfc" }.fetch(code, code)
      end

      def self.normalize_title(value)
        text = value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "").downcase
        text = text.gsub(/\bu\.s\.?(?=\s|$)/, "united states").gsub(/\bet\s+al\b/, " ").gsub(/\b(?:vs|versus)\b/, "v")
        text.scan(/[a-z0-9]+/).join(" ")
      end

      def self.number_parts(value, untyped: false)
        match = value.to_s.match(/\A\s*(?:(\d+):)?(\d{4}|\d{2})\s*-?\s*([a-z]{1,5})\s*-?\s*(\d+)(?:-[a-z0-9-]+)?\s*\z/i)
        return [match[1], match[2], match[3].downcase, match[4].to_i] if match
        return nil unless untyped

        match = value.to_s.strip.match(/\A(?:(\d+)[-:])?(\d{4}|\d{2})-(\d+)\z/)
        match && [match[1], match[2], nil, match[3].to_i]
      end

      def number_matches?(value)
        a = self.class.number_parts(number, untyped: court.end_with?("b"))
        b = self.class.number_parts(value, untyped: court.end_with?("b"))
        return false unless a && b
        year_matches = a[1].length == 4 && b[1].length == 4 ? a[1] == b[1] : a[1].to_i % 100 == b[1].to_i % 100
        year_matches && a[3] == b[3] && (a[2].nil? || b[2].nil? || a[2] == b[2]) &&
          (a[0].nil? || b[0].nil? || a[0].to_i == b[0].to_i)
      end

      def title_matches?(value)
        !value.to_s.strip.empty? && self.class.normalize_title(title) == self.class.normalize_title(value)
      end

      def verify(candidate)
        candidate = candidate.transform_keys(&:to_s)
        candidate_court = self.class.normalize_court(candidate["court_id"] || candidate["court"] || candidate["courtId"])
        candidate_id = candidate["pacer_case_id"] || candidate["caseId"]
        {
          "id" => candidate["id"] || candidate["caseId"], "court" => candidate_court,
          "pacer_case_id" => candidate_id, "docket_number" => candidate["docket_number"] || candidate["caseNumberFull"],
          "case_name" => candidate["case_name"] || candidate["caseTitle"],
          "number_matches" => number_matches?(candidate["docket_number"] || candidate["caseNumberFull"]),
          "title_matches" => [candidate["case_name"], candidate["case_name_full"], candidate["caseTitle"]].any? { |name| title_matches?(name) },
          "court_matches" => court.empty? || court == candidate_court,
          "pacer_case_id_matches" => case_id.empty? || candidate_id.to_s == case_id
        }
      end

      def self.verified?(checks)
        %w[number_matches title_matches court_matches pacer_case_id_matches].all? { |key| checks[key] }
      end

      def pacer_target
        link = first("caseUrl", "caseLink", "pacer_case_link")
        target_id = case_id
        target_court = { "arb" => "azb", "nebraskab" => "neb", "uscfc" => "cofc" }.fetch(court, court)
        if link
          uri = URI(link)
          host = uri.host.to_s.match(/\Aecf\.([a-z]+[db])\.uscourts\.gov\z/)
          raise ConfigurationError, "invalid PACER court link" unless uri.scheme == "https" && uri.port == 443 && host && !uri.userinfo
          if !court.empty? && self.class.normalize_court(host[1]) != court
            raise ConfigurationError, "court code conflicts with PACER case URL"
          end
          target_court = host[1]
          if uri.query.to_s.match?(/\A[1-9]\d*\z/)
            raise ConfigurationError, "caseId conflicts with PACER case URL" if !target_id.empty? && target_id != uri.query
            target_id = uri.query
          end
        end
        raise ConfigurationError, "PACER court and local case ID are required" unless target_court.match?(/\A[a-z]+[db]\z/) && target_id.match?(/\A[1-9]\d*\z/)
        [target_court, target_id]
      end
    end
  end
end
