# frozen_string_literal: true

require "json"
require "time"
require_relative "http"
require_relative "totp"
require_relative "docket_report"

module Juriscraper
  module Pacer
    class Client
      AUTH_URL = "https://pacer.login.uscourts.gov/services/cso-auth"
      LOGOUT_URL = "https://pacer.login.uscourts.gov/services/cso-logout"
      PCL_URL = "https://pcl.uscourts.gov/pcl-public-api/rest/cases/find"

      def initialize(username: nil, password: nil, client_code: nil, otp: nil, otp_provider: nil, totp_secret: nil, http: nil)
        config = Juriscraper.configuration
        @username = username || config.pacer_user || ENV["PACER_USER"]
        @password = password || config.pacer_pass || ENV["PACER_PASS"]
        @client_code = client_code || config.pacer_client_code || ENV["PACER_CLIENT_CODE"]
        @otp = otp || ENV["PACER_OTP_CODE"]
        @otp_provider = otp_provider
        @totp_secret = totp_secret || ENV["PACER_TOTP_SECRET"]
        @http = http || Http.new
        @session_token = nil
        @redactions = [@username, @password, @otp, @totp_secret].compact.map(&:to_s).reject(&:empty?)
      end

      def inspect
        "#<#{self.class} authenticated=#{authenticated?}>"
      end

      def authenticated?
        !@session_token.to_s.empty?
      end

      def authenticate!
        if @username.to_s.empty? || @password.to_s.empty?
          raise ConfigurationError, "Set PACER_USER and PACER_PASS, or provide PACER credentials explicitly"
        end
        body = { "loginId" => @username, "password" => @password, "redactFlag" => "1" }
        body["clientCode"] = @client_code unless @client_code.to_s.empty?
        code = next_otp
        @redactions << code.to_s unless code.to_s.empty?
        body["otpCode"] = code unless code.to_s.empty?
        response = @http.request(:post, AUTH_URL, json: body)
        ensure_success!(response, auth: true)
        payload = parse_json(response)
        unless payload["loginResult"].to_s == "0" && !payload["nextGenCSO"].to_s.empty?
          raise PacerAuthError, redact(payload["errorDescription"].to_s.empty? ? "PACER login was not accepted" : payload["errorDescription"])
        end
        @session_token = payload["nextGenCSO"]
        @redactions << @session_token.to_s
        self
      end

      def logout
        return self unless authenticated?
        response = @http.request(:post, LOGOUT_URL, json: { "nextGenCSO" => @session_token })
        ensure_success!(response, auth: true)
        raise PacerAuthError, "PACER logout was not confirmed" unless parse_json(response)["loginResult"].to_s == "0"
        self
      ensure
        @session_token = nil
      end

      def search_cases(criteria)
        authenticate! unless authenticated?
        results = []
        page = 0
        total = nil
        loop do
          response = @http.request(:post, "#{PCL_URL}?page=#{page}", json: criteria,
                                   token: @session_token, client_code: @client_code)
          ensure_success!(response)
          update_token(response)
          payload = parse_json(response)
          info = payload["pageInfo"]
          content = payload["content"]
          unless info.is_a?(Hash) && content.is_a?(Array) && content.all? { |item| item.is_a?(Hash) } && info["number"] == page &&
                 info["totalElements"].is_a?(Integer) && info["totalElements"] >= 0 &&
                 [true, false].include?(info["last"]) && info["numberOfElements"] == content.length
            raise PacerError, "invalid PCL pagination response"
          end
          total ||= info["totalElements"]
          raise PacerError, "PCL result count changed during pagination" unless total == info["totalElements"]
          results.concat(content)
          raise PacerError, "PCL returned more rows than its total count" if results.length > total
          if info["last"]
            raise PacerError, "PCL result count does not match pagination" unless info["totalElements"] == results.length
            break
          end
          raise PacerError, "empty nonfinal PCL page" if content.empty?
          page += 1
        end
        results
      end

      def find_case(record)
        identity = Dockets::Identity.new(record)
        unless identity.case_id.empty? || identity.court.empty?
          identity.pacer_target # validate the supplied court, case ID, and URL
          return identity.record
        end
        parts = Dockets::Identity.number_parts(identity.number)
        raise ConfigurationError, "unrecognized case number" unless parts
        office, year, kind, serial = parts
        compact = "#{office ? "#{office}:" : ""}#{year}#{kind}#{format('%05d', serial)}"
        candidates = search_cases("caseNumberFull" => compact)
        matches = candidates.select do |candidate|
          checks = identity.verify(candidate)
          Dockets::Identity.verified?(checks)
        end
        raise DocketNotFoundError.new("No matching PACER case", candidates: candidates) if matches.empty?
        raise AmbiguousDocketError.new("More than one PACER case matches", candidates: matches) if matches.length > 1
        identity.record.merge(matches.first)
      end

      def docket_report(record)
        resolved = find_case(record)
        identity = Dockets::Identity.new(resolved)
        court, local_id = identity.pacer_target
        authenticate! unless authenticated?
        response = @http.request(:post, "https://ecf.#{court}.uscourts.gov/cgi-bin/DktRpt.pl?1-L_1_0-1",
          token: @session_token, client_code: @client_code, form: {
            "all_case_ids" => local_id, "sort1" => "oldest date first", "date_range_type" => "Filed",
            "output_format" => "html", "case_num" => " ", "date_from" => ""
          })
        ensure_success!(response)
        update_token(response)
        # PACER may return a large-docket confirmation form. Submit that exact
        # report form, keeping all date/entry filters empty, rather than imposing
        # a date cutoff or following any filing links.
        response = confirm_report(response, court)
        report = DocketReport.new.parse(response.body, identity: identity)
        report["retrieved_at"] = Time.now.utc.iso8601
        report
      end

      private

      def confirm_report(response, court)
        return response unless response.body.match?(/report may take a long time|To accept charges shown below/i)
        doc = Nokogiri::HTML(response.body)
        form = doc.at_css("form")
        raise PacerError, "PACER returned an unrecognized report confirmation" unless form
        url = URI.join(response.url, form["action"].to_s.empty? ? response.url : form["action"]).to_s
        expected = URI("https://ecf.#{court}.uscourts.gov/cgi-bin/DktRpt.pl")
        target = URI(url)
        unless target.scheme == expected.scheme && target.host == expected.host && target.port == expected.port && target.path == expected.path
          raise PacerError, "refusing an unexpected confirmation endpoint"
        end
        fields = form.css("input[name]").each_with_object({}) do |input, values|
          next if %w[checkbox radio].include?(input["type"]) && !input.key?("checked")
          values[input["name"]] = input["value"].to_s
        end
        result = @http.request(:post, url, form: fields, token: @session_token, client_code: @client_code)
        ensure_success!(result)
        update_token(result)
        result
      end

      def next_otp
        if !@totp_secret.to_s.empty?
          TOTP.code(@totp_secret)
        elsif !@otp.to_s.empty?
          result, @otp = @otp, nil
          result
        elsif @otp_provider
          @otp_provider.call
        end
      end

      def update_token(response)
        headers = response.headers.transform_keys { |key| key.to_s.downcase }
        updated = headers["x-next-gen-cso"]
        updated ||= headers["set-cookie"].to_s[/(?:NextGenCSO|PacerSession)=([^;,\s]+)/i, 1]
        unless updated.to_s.empty?
          @session_token = updated
          @redactions << updated.to_s
        end
      end

      def ensure_success!(response, auth: false)
        return if response.success?
        detail = redact(response.body)
        if auth || [401, 403].include?(response.status)
          raise PacerAuthError, "PACER authentication/access failure (HTTP #{response.status}): #{detail}"
        end
        if response.status == 429
          raise PacerRateLimitError.new("PACER rate limit", retry_after: response.headers["retry-after"])
        end
        raise PacerError, "PACER HTTP #{response.status}: #{detail}"
      end

      def parse_json(response)
        payload = JSON.parse(response.body)
        raise PacerError, "PACER returned a non-object JSON response" unless payload.is_a?(Hash)
        payload
      rescue JSON::ParserError
        raise PacerError, "PACER returned invalid JSON"
      end

      def redact(value)
        @redactions.uniq.sort_by { |secret| -secret.length }.reduce(value.to_s) { |text, secret| text.gsub(secret, "[REDACTED]") }
      end
    end
  end
end
