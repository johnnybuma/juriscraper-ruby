# frozen_string_literal: true

require_relative "http"
require_relative "page"

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
          Set COURTLISTENER_TOKEN or Juriscraper.configuration.courtlistener_token.
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
        request(:get, "usage")
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
