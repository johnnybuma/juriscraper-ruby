# frozen_string_literal: true

require "net/http"
require "openssl"
require "thread"
require "uri"

module Juriscraper
  module HTTP
    class Client
      REDIRECT_LIMIT = 8
      RETRYABLE = [408, 425, 429, 500, 502, 503, 504].freeze

      def initialize(config: Juriscraper.configuration)
        @config = config
        @mutex = Mutex.new
        @last_request_at = nil
      end

      def get(url, headers: {}, params: nil)
        uri = URI(url)
        if params && !params.empty?
          query = URI.decode_www_form(uri.query.to_s)
          query.concat(params.map { |k, v| [k.to_s, v.to_s] })
          uri.query = URI.encode_www_form(query)
        end
        request(:get, uri, headers: headers)
      end

      def post(url, headers: {}, params: {})
        request(:post, URI(url), headers: headers, form: params)
      end

      private

      def request(method, uri, headers:, form: nil, redirects: 0)
        raise DownloadError, "too many redirects for #{uri}" if redirects > REDIRECT_LIMIT

        attempts = 0
        loop do
          begin
            throttle!
            response = perform(method, uri, headers: headers, form: form)

            if response.is_a?(Net::HTTPRedirection)
              location = response["location"]
              raise DownloadError, "redirect without Location from #{uri}" if location.to_s.empty?

              target = URI.join(uri.to_s, location)
              next_method = response.code.to_i == 303 ? :get : method
              return request(next_method, target, headers: headers, form: next_method == :post ? form : nil,
                             redirects: redirects + 1)
            end

            if RETRYABLE.include?(response.code.to_i) && attempts < @config.retries
              attempts += 1
              sleep(@config.retry_backoff * (2**(attempts - 1)))
              next
            end

            wrapped = Response.new(
              status: response.code.to_i,
              headers: response.each_header.to_h.transform_keys(&:downcase),
              body: response.body.to_s.b,
              url: uri.to_s
            )
            raise DownloadError, "HTTP #{wrapped.status} for #{uri}" unless wrapped.success?

            return wrapped
          rescue IOError, EOFError, Errno::ECONNRESET, Errno::ETIMEDOUT,
                 Net::OpenTimeout, Net::ReadTimeout, SocketError, OpenSSL::SSL::SSLError => e
            if attempts < @config.retries
              attempts += 1
              sleep(@config.retry_backoff * (2**(attempts - 1)))
              next
            end
            raise DownloadError, "request failed for #{uri}: #{e.class}: #{e.message}"
          end
        end
      end

      def perform(method, uri, headers:, form:)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @config.open_timeout
        http.read_timeout = @config.read_timeout

        klass = method == :post ? Net::HTTP::Post : Net::HTTP::Get
        req = klass.new(uri.request_uri)
        default_headers.each { |k, v| req[k] = v }
        headers.each { |k, v| req[k.to_s] = v.to_s }
        req.set_form_data(form) if method == :post && form

        http.request(req)
      end

      def default_headers
        {
          "User-Agent" => @config.user_agent,
          "Accept" => "text/html,application/xhtml+xml,application/pdf,audio/*,*/*;q=0.8",
          "Accept-Encoding" => "identity",
          "Cache-Control" => "no-cache, max-age=0, must-revalidate",
          "Pragma" => "no-cache"
        }
      end

      def throttle!
        @mutex.synchronize do
          if @last_request_at
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - @last_request_at
            delay = @config.minimum_request_interval - elapsed
            sleep(delay) if delay.positive?
          end
          @last_request_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
