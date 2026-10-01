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
end
