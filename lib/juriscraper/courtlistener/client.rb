# frozen_string_literal: true

require_relative "http"
require_relative "page"
require "time"

module Juriscraper
  module CourtListener
    # Authenticated client for https://www.courtlistener.com/api/rest/v4/
    #
    #   Juriscraper.configure { |c| c.courtlistener_token = ENV.fetch("COURTLISTENER_TOKEN") }
    #   Juriscraper::CourtListener::Client.new.search(q: "spoliation", type: :recap, court: "cacd")
    #
    # The token is sent as `Authorization: Token <key>`. It is never written to
    # disk by this client. PACER passwords passed to `recap_fetch` stay on that
    # single request.
    class Client
      SEARCH_TYPES = {
        opinions: "o",
        recap: "r",
        dockets: "d",
        documents: "rd",
        people: "p",
        oral_arguments: "oa",
        oral_args: "oa"
      }.freeze

      def initialize(token: nil, base: nil, http: nil)
        @explicit_token = token
        @base = base
        @http = http
      end

      def token
        return @explicit_token.to_s.strip unless @explicit_token.nil?

        Juriscraper.configuration.resolved_courtlistener_token
      end

      def authenticated?
        !token.empty?
      end

      def require_token!
        return self if authenticated?

        raise ConfigurationError, <<~MSG.strip
          CourtListener API token missing.
          Set COURTLISTENER_TOKEN, COURTLISTENER_API_KEY, or Juriscraper.configuration.courtlistener_token.
          Create a token at https://www.courtlistener.com/profile/api/
        MSG
      end

      def search(q: nil, type: :opinions, court: nil, order_by: "score desc", highlight: false, **extra)
        params = extra.merge(q: q, type: search_type(type), order_by: order_by)
        court_ids = Array(court).map { |id| id.to_s.strip }.reject(&:empty?)
        params[:court] = court_ids.join(" ") unless court_ids.empty?
        params[:highlight] = "on" if highlight
        get("search", params)
      end

      def usage
        request(:get, "api-usage")
      end

      def inspect
        "#<#{self.class} authenticated=#{authenticated?}>"
      end

      # PACER IDs repeat across courts. Scan every cursor, then verify all
      # identity fields before selecting a docket; never select results.first.
      def find_docket(record = {}, **identity_fields)
        identity = Dockets::Identity.new(record, **identity_fields)
        raise ConfigurationError, "pacer_case_id/caseId is required" if identity.case_id.empty?
        page = dockets(pacer_case_id: identity.case_id, order_by: "id", omit: "audio_files,clusters")
        raise CourtListenerError, "docket search was not paginated" unless page.is_a?(Page)
        candidates = page.each_result.to_a.uniq
        unless candidates.all? { |candidate| candidate.is_a?(Hash) && candidate["id"].is_a?(Integer) && candidate["id"].positive? }
          raise CourtListenerError, "invalid docket search result"
        end
        checks = candidates.map { |candidate| [candidate, identity.verify(candidate)] }
        matches = checks.select { |_candidate, result| Dockets::Identity.verified?(result) }.uniq { |candidate, _result| candidate["id"] }
        if matches.empty?
          raise DocketNotFoundError.new("No CourtListener docket passed the number/title/court/PACER-ID checks", candidates: checks.map(&:last))
        end
        if matches.length > 1
          raise AmbiguousDocketError.new("Multiple CourtListener dockets passed identity checks", candidates: matches.map(&:last))
        end
        matches.first.first
      end

      def docket_report(record = {}, **identity_fields)
        metadata = find_docket(record, **identity_fields)
        page = docket_entries(docket: metadata.fetch("id"), order_by: "id", omit: "recap_documents")
        raise CourtListenerError, "entry list was not paginated" unless page.is_a?(Page)
        seen = {}
        entries = page.each_result.map do |entry|
          joined_id = entry["docket_id"] || entry["docket"]
          joined_id = joined_id.to_s.sub(%r{/$}, "").split("/").last
          raise CourtListenerError, "entry belongs to a different docket" unless joined_id == metadata["id"].to_s
          id = entry["id"]
          raise CourtListenerError, "missing or repeated docket-entry ID" if id.nil? || seen[id]
          raise CourtListenerError, "entry lacks text/date/number fields" unless %w[description date_filed entry_number].all? { |key| entry.key?(key) }
          seen[id] = true
          entry.reject { |key, _value| %w[recap_documents documents plain_text filepath_local].include?(key) }
        end
        count = request(:get, "docket-entries", params: { docket: metadata["id"], count: "on" })["count"]
        raise CourtListenerError, "entry count verification failed" unless count.is_a?(Integer) && count == entries.length
        { "source" => "courtlistener", "metadata" => metadata, "docket_entries" => entries,
          "entry_count" => entries.length, "api_count_verified" => true, "retrieved_at" => Time.now.utc.iso8601 }
      end

      def dockets(params = {})
        get("dockets", params)
      end

      def docket(id)
        request(:get, "dockets/#{id}")
      end

      def docket_entries(params = {})
        get("docket-entries", params)
      end

      def recap_documents(params = {})
        get("recap-documents", params)
      end

      def parties(params = {})
        get("parties", params)
      end

      def attorneys(params = {})
        get("attorneys", params)
      end

      def courts(params = {})
        get("courts", params)
      end

      def court(id)
        request(:get, "courts/#{id}")
      end

      def clusters(params = {})
        get("clusters", params)
      end

      def cluster(id)
        request(:get, "clusters/#{id}")
      end

      def opinions(params = {})
        get("opinions", params)
      end

      def opinion(id)
        request(:get, "opinions/#{id}")
      end

      def people(params = {})
        get("people", params)
      end

      def oral_arguments(params = {})
        get("audio", params)
      end

      def citations(params = {})
        get("citations", params)
      end

      def citation_lookup(text:)
        request(:post, "citation-lookup", form: { text: text })
      end

      # Live PACER pull. CourtListener mints a session cookie and does not store
      # the password. MFA is not supported.
      def recap_fetch(court:, pacer_username:, pacer_password:, **extra)
        request(:post, "recap-fetch", body: extra.merge(
          court: court,
          pacer_username: pacer_username,
          pacer_password: pacer_password
        ))
      end

      def get(resource, params = {})
        payload = request(:get, resource, params: params)
        paginated?(payload) ? Page.new(payload, client: self) : payload
      end

      def post(resource, body = {})
        request(:post, resource, body: body)
      end

      def get_url(url)
        payload = http.request(:get, url)
        paginated?(payload) ? Page.new(payload, client: self) : payload
      end

      def request(method, resource, params: {}, body: nil, form: nil)
        http.request(method, resource, params: params, body: body, form: form)
      end

      private

      def http
        @http ||= Http.new(
          base: @base || Juriscraper.configuration.courtlistener_api_base,
          token: token,
          open_timeout: Juriscraper.configuration.open_timeout,
          read_timeout: Juriscraper.configuration.read_timeout,
          user_agent: Juriscraper.configuration.user_agent
        )
      end

      def search_type(type)
        key = type.to_sym
        return SEARCH_TYPES[key] if SEARCH_TYPES.key?(key)

        type.to_s
      end

      def paginated?(payload)
        payload.is_a?(Hash) && (payload.key?("results") || payload.key?("next") || payload.key?("count"))
      end
    end
  end
end
