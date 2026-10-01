# frozen_string_literal: true

module Juriscraper
  class Registry
    include Enumerable

    def initialize
      @scrapers = {}
    end

    def register(id, klass, aliases: [])
      ([id] + aliases).each { |name| @scrapers[normalize(name)] = klass }
      klass
    end

    def fetch(id)
      @scrapers.fetch(normalize(id)) do
        raise ScraperNotFoundError, "unknown scraper #{id.inspect}; available: #{ids.join(', ')}"
      end
    end

    def build(id, **kwargs)
      fetch(id).new(**kwargs)
    end

    def ids
      @scrapers.keys.sort
    end

    def each(&block)
      @scrapers.each(&block)
    end

    private

    def normalize(id)
      id.to_s.downcase.strip
    end
  end
end
