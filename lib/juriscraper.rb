# frozen_string_literal: true

require "logger"
require_relative "juriscraper/version"
require_relative "juriscraper/errors"
require_relative "juriscraper/configuration"
require_relative "juriscraper/utils/date_utils"
require_relative "juriscraper/utils/string_utils"
require_relative "juriscraper/http/response"
require_relative "juriscraper/http/client"
require_relative "juriscraper/abstract_site"
require_relative "juriscraper/opinion_site"
require_relative "juriscraper/opinion_site_linear"
require_relative "juriscraper/oral_argument_site"
require_relative "juriscraper/registry"
require_relative "juriscraper/python_bridge"
require_relative "juriscraper/scrapers/united_states/federal_appellate/ca1"
require_relative "juriscraper/scrapers/united_states/federal_appellate/ca9"
require_relative "juriscraper/integrations/capo_virtual"
require_relative "juriscraper/cli"

module Juriscraper
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
      configuration
    end

    def registry
      @registry ||= Registry.new
    end

    def register(id, klass, aliases: [])
      registry.register(id, klass, aliases: aliases)
    end
  end
end

Juriscraper.register(
  "ca1",
  Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA1,
  aliases: ["first_circuit", "us_ca1"]
)

Juriscraper.register(
  "ca9_p",
  Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA9Published,
  aliases: ["ca9", "ninth_circuit", "ninth_circuit_published"]
)

Juriscraper.register(
  "ca9_u",
  Juriscraper::Scrapers::UnitedStates::FederalAppellate::CA9Unpublished,
  aliases: ["ninth_circuit_unpublished"]
)

require_relative "juriscraper/integrations/capo_virtual_railtie" if defined?(Rails::Railtie)
