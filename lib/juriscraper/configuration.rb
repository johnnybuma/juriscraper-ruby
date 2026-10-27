# frozen_string_literal: true

module Juriscraper
  class Configuration
    attr_accessor :user_agent, :open_timeout, :read_timeout, :retries,
                  :retry_backoff, :minimum_request_interval, :logger,
                  :courtlistener_token, :courtlistener_base

    def initialize
      @user_agent = "Juriscraper-Ruby/#{Juriscraper::VERSION}"
      @open_timeout = 15
      @read_timeout = 90
      @retries = 2
      @retry_backoff = 0.5
      @minimum_request_interval = 0.25
      @logger = Logger.new($stderr)
      @logger.level = Logger.const_get(ENV.fetch("JURISCRAPER_LOG_LEVEL", "WARN").upcase)
      # nil reads COURTLISTENER_TOKEN at call time. "" forces an unauthenticated request.
      @courtlistener_token = nil
      @courtlistener_base = nil
    end

    def courtlistener_api_base
      base = @courtlistener_base
      base = ENV["COURTLISTENER_API_BASE"] if base.nil? || base.to_s.strip.empty?
      base = "https://www.courtlistener.com/api/rest/v4" if base.nil? || base.to_s.strip.empty?
      base.to_s.chomp("/")
    end

    # Explicit config wins, including a blank string. Otherwise the env var.
    def resolved_courtlistener_token
      return @courtlistener_token.to_s.strip unless @courtlistener_token.nil?

      ENV["COURTLISTENER_TOKEN"].to_s.strip
    end
  end
end
