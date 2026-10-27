# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "openssl"

module Juriscraper
  module Pacer
    # Read-only court-report transport. It never follows document links or
    # redirects credentials to another host. Billable POSTs are not retried.
    class Http
      def initialize(config: Juriscraper.configuration)
        @config = config
      end

      def request(method, url, json: nil, form: nil, token: nil, client_code: nil)
        uri = URI(url)
        kind = endpoint_kind(uri)
        raise PacerError, "unsupported PACER request method" unless method == :post
        req = Net::HTTP::Post.new(uri.request_uri)
        req["User-Agent"] = @config.user_agent
        req["Accept"] = kind == :report ? "text/html" : "application/json"
        if kind == :pcl
          req["X-NEXT-GEN-CSO"] = token.to_s
          req["X-CLIENT-CODE"] = client_code.to_s unless client_code.to_s.empty?
        elsif kind == :report
          req["Cookie"] = "NextGenCSO=#{safe_cookie(token)}; PacerSession=#{safe_cookie(token)}"
          req["Cookie"] += "; PacerClientCode=#{safe_cookie(client_code)}" unless client_code.to_s.empty?
        end
        if form
          req.set_form_data(form)
        else
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(json || {})
        end
        if @last_request_at
          delay = @config.minimum_request_interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at)
          sleep(delay) if delay.positive?
        end
        @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = transmit(uri, req)
        if response.is_a?(Net::HTTPRedirection)
          raise PacerAuthError, "PACER returned a redirect; reauthenticate rather than forwarding credentials"
        end
        HTTP::Response.new(status: response.code.to_i, headers: response.each_header.to_h,
                           body: response.body.to_s, url: uri.to_s)
      rescue IOError, EOFError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
        raise PacerError, "PACER request failed: #{e.class}"
      end

      def endpoint_kind(uri)
        raise PacerError, "PACER requires HTTPS on port 443" unless uri.scheme == "https" && uri.port == 443 && !uri.userinfo && !uri.fragment
        return :auth if uri.host == "pacer.login.uscourts.gov" && %w[/services/cso-auth /services/cso-logout].include?(uri.path)
        return :pcl if uri.host == "pcl.uscourts.gov" && uri.path == "/pcl-public-api/rest/cases/find"
        return :report if uri.host.to_s.match?(/\Aecf\.[a-z]+[db]\.uscourts\.gov\z/) && uri.path == "/cgi-bin/DktRpt.pl"
        raise PacerError, "refusing endpoint outside authentication, case search, and docket reports"
      end

      private

      def safe_cookie(value)
        raw = value.to_s
        raise ConfigurationError, "invalid PACER cookie value" if raw.match?(/[;\x00-\x20\x7f]/)
        raw
      end

      def transmit(uri, request)
        connection = Net::HTTP.new(uri.host, uri.port)
        connection.use_ssl = true
        connection.open_timeout = @config.open_timeout
        connection.read_timeout = @config.read_timeout
        connection.request(request)
      end
    end
  end
end
