# frozen_string_literal: true

require_relative "lib/juriscraper/version"

Gem::Specification.new do |spec|
  spec.name = "juriscraper-ruby"
  spec.version = Juriscraper::VERSION
  spec.authors = ["Juriscraper Ruby contributors"]
  spec.summary = "Ruby court scrapers, PACER docket reports, and CourtListener REST v4"
  spec.description = <<~DESC
    A Ruby implementation of the core Juriscraper scraping model: enumerable court
    sites, opinion/oral-argument metadata extraction, content downloading, sanity
    checks, date sorting, a scraper registry, and an optional bridge to the upstream
    Python Juriscraper package for broad court coverage. Includes a CourtListener
    REST v4 client with verified docket matching and complete entry pagination,
    plus native PACER authentication, MFA, case search, and HTML docket reports.
  DESC
  spec.license = "BSD-2-Clause"
  spec.required_ruby_version = ">= 3.1"
  spec.homepage = "https://github.com/johnnybuma/juriscraper-ruby"

  spec.metadata["source_code_uri"] = "https://github.com/johnnybuma/juriscraper-ruby"
  spec.metadata["changelog_uri"] = "https://github.com/johnnybuma/juriscraper-ruby/blob/master/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib,exe,examples}/**/*", "README.md", "LICENSE", "NOTICE", "CHANGELOG.md"].select { |path| File.file?(path) }
  end
  spec.bindir = "exe"
  spec.executables = ["juriscraper"]
  spec.require_paths = ["lib"]

  spec.add_dependency "nokogiri", ">= 1.16", "< 2"
  spec.add_dependency "logger", ">= 1.5", "< 2"
end
