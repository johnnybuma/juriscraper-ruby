# frozen_string_literal: true

require "juriscraper"

site = Juriscraper.registry.build("ca1").parse
puts JSON.pretty_generate(site.to_a)
