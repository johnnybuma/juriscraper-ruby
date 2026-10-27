# frozen_string_literal: true

module Juriscraper
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class DownloadError < Error; end
  class EmptyFileError < DownloadError; end
  class UnexpectedContentTypeError < DownloadError; end
  class ParsingError < Error; end
  class SanityError < Error; end
  class ScraperNotFoundError < Error; end
  class UpstreamBridgeError < Error; end
  class DocketNotFoundError < Error
    attr_reader :candidates

    def initialize(message = nil, candidates: [])
      super(message)
      @candidates = candidates
    end
  end
  class AmbiguousDocketError < DocketNotFoundError; end
  class PacerError < Error; end
  class PacerAuthError < PacerError; end
  class PacerRateLimitError < PacerError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end

  class CourtListenerError < Error; end
  class CourtListenerAuthError < CourtListenerError; end
  class CourtListenerNotFoundError < CourtListenerError; end
  class CourtListenerRateLimitError < CourtListenerError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil)
      super(message)
      @retry_after = retry_after
    end
  end
end
