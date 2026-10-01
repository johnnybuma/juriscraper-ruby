# frozen_string_literal: true

module Juriscraper
  class Configuration
    attr_accessor :user_agent, :open_timeout, :read_timeout, :retries,
                  :retry_backoff, :minimum_request_interval, :logger

    def initialize
      @user_agent = "Juriscraper-Ruby/#{Juriscraper::VERSION}"
      @open_timeout = 15
      @read_timeout = 90
      @retries = 2
      @retry_backoff = 0.5
      @minimum_request_interval = 0.25
      @logger = Logger.new($stderr)
      @logger.level = Logger.const_get(ENV.fetch("JURISCRAPER_LOG_LEVEL", "WARN").upcase)
    end
  end
end
