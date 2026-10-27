# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

module Juriscraper
  module CourtListener
    # JSON transport for CourtListener REST v4.
    # Sends `Authorization: Token <key>` only to the configured API host.
    class Http
      REDIRECT_LIMIT = 5

      def initialize(base:, token:, open_timeout:, read_timeout:, user_agent:)
        @base = base.chomp("/")
        @token = sanitize_token(token)
        @open_timeout = open_timeout
        @read_timeout = read_timeout
        @user_agent = user_agent
        @origin = URI(@base)
      end

      attr_reader :token

      def request(method, path, params: {}, body: nil, form: nil)
        uri = build_uri(path, params)
        perform(method, uri, body: body, form: form, redirects: 0)
      end

      def build_uri(path, params = {})
        uri = coerce_uri(path)
        filtered = stringify_params(params)
        unless filtered.empty?
          existing = URI.decode_www_form(uri.query.to_s)
          uri.query = URI.encode_www_form(existing + filtered.to_a)
        end
        uri
      end

      def build_request(method, uri, body: nil, form: nil)
        klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
        req = klass.new(uri.request_uri)
        req["Accept"] = "application/json"
        req["User-Agent"] = @user_agent
        req["Authorization"] = "Token #{@token}" unless @token.empty?
        if method == :post && form
          req.set_form_data(stringify_params(form))
        elsif method == :post
          req["Content-Type"] = "application/json"
          req.body = JSON.generate(body || {})
        end
        req
      end

      def interpret(status:, body:, headers: {})
        payload = parse_json(body)
        detail = extract_detail(payload, status)
        case status.to_i
        when 200..299
          payload
        when 401, 403
          raise CourtListenerAuthError, detail
        when 404
          raise CourtListenerNotFoundError, detail
        when 429
          retry_after = header_value(headers, "retry-after")
          raise CourtListenerRateLimitError.new(detail, retry_after: retry_after)
        else
          raise CourtListenerError, detail
        end
      end

      private

      def perform(method, uri, body:, form:, redirects:)
        raise CourtListenerError, "too many redirects for #{uri}" if redirects > REDIRECT_LIMIT

        # Drop the token if a redirect ever leaves the API host.
        authed = same_origin?(uri) ? self : self.class.new(
          base: @base,
          token: "",
          open_timeout: @open_timeout,
          read_timeout: @read_timeout,
          user_agent: @user_agent
        )
        response = authed.send(:transmit, method, uri, body: body, form: form)

        if response.is_a?(Net::HTTPRedirection)
          location = response["location"].to_s
          raise CourtListenerError, "redirect without Location from #{uri}" if location.empty?

          target = URI.join(uri.to_s, location)
          next_method = response.code.to_i == 303 ? :get : method
          next_body = next_method == :post ? body : nil
          next_form = next_method == :post ? form : nil
          return perform(next_method, target, body: next_body, form: next_form, redirects: redirects + 1)
        end

        interpret(
          status: response.code.to_i,
          body: response.body.to_s,
          headers: response.each_header.to_h
        )
      rescue IOError, EOFError, Errno::ECONNRESET, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
             Net::OpenTimeout, Net::ReadTimeout, SocketError => e
        raise CourtListenerError, "request failed for #{uri.host}: #{e.class}: #{e.message}"
      end

      def transmit(method, uri, body:, form:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @read_timeout
        http.request(build_request(method, uri, body: body, form: form))
      end

      def coerce_uri(path)
        raw = path.to_s.strip
        raise ArgumentError, "CourtListener path is required" if raw.empty?

        uri =
          if raw.start_with?("http://", "https://")
            parsed = URI(raw)
            unless same_origin?(parsed)
              raise CourtListenerError, "refusing CourtListener request to #{parsed.host}"
            end
            parsed
          else
            raise ArgumentError, "invalid CourtListener path" if raw.include?("..") || raw.include?("://")

            URI("#{@base}/#{raw.sub(%r{\A/}, "")}")
          end
        uri.path = "#{uri.path}/" unless uri.path.end_with?("/")
        uri
      end

      def same_origin?(uri)
        uri.host == @origin.host && uri.scheme == @origin.scheme
      end

      def stringify_params(params)
        Array(params).each_with_object({}) do |(key, value), acc|
          next if value.nil? || value == ""

          acc[key.to_s] =
            case value
            when Array then value.join(" ")
            when true then "true"
            when false then "false"
            else value.to_s
            end
        end
      end

      def parse_json(body)
        return {} if body.nil? || body.empty?

        JSON.parse(body)
      rescue JSON::ParserError
        { "detail" => body.to_s[0, 500] }
      end

      def extract_detail(payload, status)
        return payload["detail"] if payload.is_a?(Hash) && payload["detail"].is_a?(String) && !payload["detail"].empty?

        "HTTP #{status}"
      end

      def header_value(headers, name)
        return nil unless headers

        headers[name] || headers[name.to_s.downcase] || headers[name.to_s]
      end

      def sanitize_token(token)
        value = token.to_s.strip
        return "" if value.empty?
        if value.match?(/[[:space:]\x00-\x1f]/)
          raise ConfigurationError, "CourtListener token contains whitespace or control characters"
        end

        value
      end
    end
  end
end
