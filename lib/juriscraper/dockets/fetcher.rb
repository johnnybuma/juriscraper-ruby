# frozen_string_literal: true

module Juriscraper
  module Dockets
    class Fetcher
      SOURCES = %i[pacer courtlistener both].freeze

      def initialize(pacer: nil, courtlistener: nil, otp_provider: nil, pacer_options: {})
        @pacer = pacer
        @courtlistener = courtlistener
        @otp_provider = otp_provider
        @pacer_options = pacer_options
      end

      def fetch(record, source: :courtlistener, previous: nil)
        source = source.to_sym
        raise ConfigurationError, "source must be pacer, courtlistener, or both" unless SOURCES.include?(source)
        identity = Identity.new(record)
        if previous
          prior = Identity.new(previous.fetch("case"))
          unless previous["selected_source"] == source.to_s && identity.case_id == prior.case_id && identity.court == prior.court &&
                 identity.number_matches?(prior.number) && identity.title_matches?(prior.title)
            raise ConfigurationError, "previous result belongs to a different case or source"
          end
        end
        names = source == :both ? %i[pacer courtlistener] : [source]
        results = {}
        names.each do |name|
          cached = previous && previous.dig("sources", name.to_s)
          begin
            results[name.to_s] = cached && cached["status"] == "complete" ? cached : fetch_source(name, record)
          rescue Juriscraper::Error => e
            raise unless source == :both
            results[name.to_s] = { "source" => name.to_s, "status" => "error", "error_class" => e.class.name, "message" => e.message }
            results[name.to_s]["candidates"] = e.candidates if e.respond_to?(:candidates)
          end
        end
        fallback = nil
        if source != :both && no_results?(results.fetch(source.to_s))
          fallback = source == :pacer ? :courtlistener : :pacer
          results[fallback.to_s] = fetch_source(fallback, record)
        end
        complete = results.values.any? { |result| result["status"] == "complete" }
        errors = results.values.any? { |result| result["status"] == "error" }
        status = errors ? (complete ? "partial" : "error") : (complete ? "complete" : "not_found")
        { "case" => record, "status" => status, "selected_source" => source.to_s,
          "fallback_source" => fallback&.to_s, "sources" => results }
      end

      def close
        @pacer.logout if @pacer && @pacer.respond_to?(:authenticated?) && @pacer.authenticated?
      end

      private

      def fetch_source(name, record)
        client = if name == :pacer
          @pacer ||= Pacer::Client.new(**@pacer_options, otp_provider: @otp_provider)
        else
          @courtlistener ||= CourtListener::Client.new.require_token!
        end
        report = client.docket_report(record)
        count = report.fetch("docket_entries").length
        report.merge("status" => count.zero? ? "no_entries" : "complete", "entry_count" => count)
      rescue AmbiguousDocketError
        raise
      rescue DocketNotFoundError => e
        { "source" => name.to_s, "status" => "not_found", "docket_entries" => [], "entry_count" => 0,
          "message" => e.message, "candidates" => e.candidates }
      end

      def no_results?(result)
        %w[not_found no_entries].include?(result["status"])
      end
    end
  end
end
