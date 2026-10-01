# frozen_string_literal: true

require "set"

module Juriscraper
  module Integrations
    module CapoVirtual
      ID_KEYS = %i[
        authority_ids context_authority_ids legal_authority_ids live_authority_ids
        new_authority_ids stored_authority_ids
      ].freeze
      ARRAY_KEYS = (ID_KEYS + %i[visited_urls errors rejections candidates]).freeze

      class Configuration
        attr_accessor :enabled, :court_ids, :max_seed_opinions

        def initialize
          @enabled = env_boolean("JURISCRAPER_CAPO_ENABLED", true)
          @court_ids = ENV.fetch("JURISCRAPER_CAPO_COURTS", "ca9_p,ca9_u")
                          .split(",")
                          .map(&:strip)
                          .reject(&:empty?)
          @max_seed_opinions = positive_integer(ENV["JURISCRAPER_CAPO_MAX_SEEDS"], 8)
        end

        private

        def env_boolean(name, default)
          raw = ENV[name]
          return default if raw.nil? || raw.strip.empty?

          !raw.match?(/\A(?:0|false|off|no)\z/i)
        end

        def positive_integer(raw, default)
          parsed = raw.to_i
          parsed.positive? ? parsed : default
        end
      end

      class AuthorityDiscovery
        STOP_WORDS = Set.new(%w[
          a an and are as at be by case cases court courts decision decisions for from in into
          is law legal of on opinion opinions or precedent the to v vs with
        ]).freeze

        def initialize(query:, court_ids:, limit:, registry: Juriscraper.registry)
          @query = query.to_s
          @court_ids = Array(court_ids).map(&:to_s).reject(&:empty?).uniq
          @limit = [limit.to_i, 1].max
          @registry = registry
        end

        def call
          rows = @court_ids.flat_map { |court_id| scrape(court_id) }
          rows
            .uniq { |row| row.fetch(:download_url) }
            .sort_by { |row| [relevance_score(row), row[:date_filed] || Date.new(1, 1, 1)] }
            .reverse
            .first(@limit)
        end

        private

        def scrape(court_id)
          site = @registry.build(court_id).parse
          site.map do |row|
            download_url = row[:download_urls].to_s.strip
            next if download_url.empty?

            {
              court_id: site.court_id.to_s,
              case_name: row[:case_names].to_s,
              docket_number: row[:docket_numbers].to_s,
              date_filed: row[:case_dates],
              precedential_status: row[:precedential_statuses].to_s,
              download_url: download_url
            }
          end.compact
        rescue StandardError => e
          Juriscraper.configuration.logger.warn(
            "CapoVirtual Juriscraper discovery skipped #{court_id}: #{e.class}: #{e.message}"
          )
          []
        end

        def relevance_score(row)
          terms = query_terms
          return 0 if terms.empty?

          haystack = [
            row[:case_name], row[:docket_number], row[:precedential_status], row[:court_id]
          ].join(" ").downcase
          terms.sum { |term| haystack.include?(term) ? 1 : 0 }
        end

        def query_terms
          @query_terms ||= @query
                           .downcase
                           .scan(/[a-z0-9][a-z0-9.'§-]{2,}/)
                           .reject { |term| STOP_WORDS.include?(term) }
                           .uniq
                           .first(24)
        end
      end

      module LegalAuthorityHook
        def scrape_web!(query: nil, seeds: [], profiles: [], **options)
          integration = Juriscraper::Integrations::CapoVirtual
          return super unless integration.enabled_for?(options)

          discovery = integration.discover(query: query)
          official_urls = discovery.map { |row| row.fetch(:download_url) }
          return super if official_urls.empty?

          official_result = {}
          official_error = nil
          begin
            Thread.current[:juriscraper_capo_official_ingest] = true
            official_result = super(
              query: nil,
              seeds: official_urls,
              profiles: [],
              sites: [:uscourts],
              max_pages: official_urls.length,
              max_depth: 0,
              min_new_authorities: [options.fetch(:min_new_authorities, 1).to_i, 1].max,
              case_law_only: false,
              embed_inline: options.fetch(:embed_inline, true),
              progress_callback: nil
            )
          rescue StandardError => e
            official_error = e
            Juriscraper.configuration.logger.warn(
              "CapoVirtual official-court ingest skipped: #{e.class}: #{e.message}"
            )
          ensure
            Thread.current[:juriscraper_capo_official_ingest] = false
          end

          primary_result = super(query: query, seeds: seeds, profiles: profiles, **options)
          integration.merge_results(
            primary_result,
            official_result,
            discovery: discovery,
            official_error: official_error
          )
        end
      end

      class << self
        def configuration
          @configuration ||= Configuration.new
        end

        def configure
          yield configuration
          configuration
        end

        def install!(legal_authority_class: nil)
          klass = legal_authority_class || detect_legal_authority_class
          return false unless klass
          return true if klass.singleton_class.ancestors.include?(LegalAuthorityHook)

          klass.singleton_class.prepend(LegalAuthorityHook)
          true
        end

        def installed?(legal_authority_class: nil)
          klass = legal_authority_class || detect_legal_authority_class
          klass && klass.singleton_class.ancestors.include?(LegalAuthorityHook)
        end

        def enabled_for?(options)
          return false unless configuration.enabled
          return false unless truthy?(options[:case_law_only])
          return false if Thread.current[:juriscraper_capo_official_ingest]

          true
        end

        def discover(query: nil, court_ids: configuration.court_ids, limit: configuration.max_seed_opinions)
          AuthorityDiscovery.new(query: query, court_ids: court_ids, limit: limit).call
        end

        def merge_results(primary, official, discovery: [], official_error: nil)
          primary = symbolize_hash(primary)
          official = symbolize_hash(official)
          merged = primary.dup

          ARRAY_KEYS.each do |key|
            values = Array(primary[key]) + Array(official[key])
            merged[key] = key == :errors || key == :rejections || key == :candidates ? values.compact : values.compact.uniq
          end

          merged[:authority_ids] = merged_ids(merged, :authority_ids)
          merged[:new_authority_ids] = merged_ids(merged, :new_authority_ids)
          merged[:persisted_count] = merged[:authority_ids].length if merged[:authority_ids].any?
          merged[:new_persisted_count] = merged[:new_authority_ids].length if merged[:new_authority_ids].any?
          merged[:visited_count] = if merged[:visited_urls].any?
            merged[:visited_urls].length
          else
            primary[:visited_count].to_i + official[:visited_count].to_i
          end
          merged[:candidate_count] = primary[:candidate_count].to_i + official[:candidate_count].to_i
          merged[:error_count] = merged[:errors].length
          merged[:rejection_count] = merged[:rejections].length
          merged[:juriscraper] = {
            source: "official_court_opinion_feeds",
            court_ids: discovery.map { |row| row[:court_id] }.compact.uniq,
            discovered_count: discovery.length,
            seed_urls: discovery.map { |row| row[:download_url] }.compact.uniq,
            opinions: discovery.map { |row| serialize_discovery_row(row) },
            persisted_authority_ids: Array(official[:authority_ids]).map(&:to_i).select(&:positive?).uniq,
            new_authority_ids: Array(official[:new_authority_ids]).map(&:to_i).select(&:positive?).uniq,
            error: official_error && "#{official_error.class}: #{official_error.message}"
          }.compact
          merged
        end

        private

        def merged_ids(hash, key)
          Array(hash[key]).map(&:to_i).select(&:positive?).uniq
        end

        def serialize_discovery_row(row)
          row.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }
        end

        def symbolize_hash(value)
          return {} unless value.respond_to?(:to_h)

          value.to_h.each_with_object({}) { |(key, val), memo| memo[key.to_sym] = val }
        end

        def detect_legal_authority_class
          return nil unless Object.const_defined?(:LegalAuthority)

          Object.const_get(:LegalAuthority)
        end

        def truthy?(value)
          value == true || value.to_s.match?(/\A(?:1|true|on|yes)\z/i)
        end
      end
    end
  end
end
