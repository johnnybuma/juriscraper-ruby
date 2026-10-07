# frozen_string_literal: true

require "juriscraper"

# Token from https://www.courtlistener.com/profile/api/
# Sent as: Authorization: Token <key>
Juriscraper.configure do |config|
  config.courtlistener_token = ENV.fetch("COURTLISTENER_TOKEN")
end

client = Juriscraper::CourtListener::Client.new.require_token!

page = client.search(q: "qualified immunity", type: :opinions, court: "ca9")
page.each do |hit|
  puts [hit["caseName"], hit["docketNumber"], hit["dateFiled"]].join(" — ")
end

puts client.usage
