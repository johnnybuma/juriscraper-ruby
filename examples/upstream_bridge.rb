# frozen_string_literal: true

require "juriscraper"

bridge = Juriscraper::PythonBridge.new
rows = bridge.scrape("juriscraper.opinions.united_states.federal_appellate.ca1")
puts JSON.pretty_generate(rows)
