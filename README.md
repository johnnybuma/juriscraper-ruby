# juriscraper-ruby

`juriscraper-ruby` is a Ruby implementation of the core ideas and caller-facing behavior of [Free Law Project's Juriscraper](https://github.com/freelawproject/juriscraper): court-site scrapers with a common lifecycle, normalized metadata, enumerable results, JSON output, document downloading, and reusable opinion/oral-argument base classes.

It has two layers:

1. **Native Ruby framework.** Build and run court scrapers without Python. The initial release includes a native First Circuit (`ca1`) opinion scraper and the framework needed to port additional courts.
2. **Optional upstream bridge.** If the Python `juriscraper` package is installed, Ruby can invoke any existing upstream scraper module. This provides broad coverage immediately while individual scrapers are migrated to native Ruby.

This project is independent from Free Law Project. See `NOTICE`.

## Requirements

- Ruby 3.1+ (including Ruby 4.x)
- Nokogiri 1.16+
- Optional: Python 3.10+ with `juriscraper` installed for `PythonBridge`

## Install

From this source tree:

```bash
bundle install
bundle exec rake test
gem build juriscraper-ruby.gemspec
gem install ./juriscraper-ruby-0.1.0.gem
```

Or in a Gemfile after publication:

```ruby
gem "juriscraper-ruby"
```

The require path is intentionally short:

```ruby
require "juriscraper"
```

## Native usage

```ruby
require "juriscraper"

site = Juriscraper.registry.build("ca1")
site.parse

puts site.to_json
site.each do |opinion|
  p opinion
end
```

The result keys follow Juriscraper's metadata names, for example:

```ruby
{
  case_dates: Date.new(2026, 9, 30),
  case_names: "Smith v. Jones",
  download_urls: "https://www.ca1.uscourts.gov/opn/...pdf",
  precedential_statuses: "Published",
  blocked_statuses: false,
  date_filed_is_approximate: false,
  docket_numbers: "24-1234"
}
```

### Parse saved HTML

Network access is not required when you already have a court page:

```ruby
html = File.binread("ca1.html")
site = Juriscraper.registry.build("ca1", content: html).parse
```

CLI equivalent:

```bash
juriscraper scrape ca1 --file ca1.html --pretty
```

## Optional full upstream coverage

Install the Python package in the Python environment Ruby should call:

```bash
python3 -m pip install juriscraper
```

Then:

```ruby
require "juriscraper"

bridge = Juriscraper::PythonBridge.new
rows = bridge.scrape("juriscraper.opinions.united_states.federal_appellate.ca1")
puts JSON.pretty_generate(rows)
```

Or:

```bash
juriscraper upstream juriscraper.opinions.united_states.federal_appellate.ca1 --pretty
```

Set `JURISCRAPER_PYTHON=/path/to/python` or pass `python:` to select a virtualenv interpreter. The bridge detects both synchronous and asynchronous upstream `Site#parse` implementations.

## Porting a court scraper to Ruby

For row-oriented opinion pages, inherit from `Juriscraper::OpinionSiteLinear` and implement `process_html`:

```ruby
class ExampleCourt < Juriscraper::OpinionSiteLinear
  def initialize(**kwargs)
    super
    self.court_id = "example"
    self.url = "https://court.example/opinions"
    self.status = "Published"
  end

  protected

  def process_html
    html.css("table.opinions tr").each do |row|
      link = row.at_css("a.opinion")
      next unless link

      cases << {
        name: row.at_css(".case-name")&.text,
        url: link["href"],
        date: row.at_css("time")&.text,
        docket: row.at_css(".docket")&.text
      }
    end
  end
end

Juriscraper.register("example", ExampleCourt)
```

Recognized linear keys include `name`, `url`, `date`, `status`, `docket`, `judge`, `citation`, `summary`, `lower_court`, `author`, `per_curiam`, `type`, `attorney`, `headnote`, and `content`.

For non-linear pages, inherit from `Juriscraper::OpinionSite` directly and implement `get_case_names`, `get_case_dates`, `get_download_urls`, and `get_precedential_statuses`.

## Scraper lifecycle

`AbstractSite#parse` performs the following:

1. Download the configured page unless `content:` was supplied.
2. Parse HTML with Nokogiri.
3. Run `process_html`.
4. Evaluate every required and optional metadata getter.
5. Normalize strings and dates.
6. Generate short case names.
7. Run the `post_parse` hook.
8. Verify parallel-array lengths, required values, case names, and dates.
9. Sort all parallel metadata arrays by filing date descending.
10. Generate a stable SHA-1 `snapshot_hash` from case names.

This deliberately mirrors the useful parts of Juriscraper's site lifecycle while keeping the Ruby implementation synchronous and idiomatic. One deliberate Ruby-specific divergence is `snapshot_hash`: the Python project exposes a string attribute named `hash`, but Ruby reserves `Object#hash` for integer object hashing, so this gem does not override it.

## HTTP behavior

`Juriscraper::HTTP::Client` uses Ruby's `Net::HTTP` and includes:

- configurable user agent;
- `GET` and form `POST`;
- redirect handling;
- retry/backoff for transient HTTP statuses and network failures;
- per-client minimum request interval;
- no-cache request headers;
- content-type validation for downloaded PDFs/audio.

Configure globally:

```ruby
Juriscraper.configure do |config|
  config.user_agent = "MyCourtResearchBot/1.0 contact@example.com"
  config.minimum_request_interval = 1.0
  config.read_timeout = 120
  config.retries = 3
end
```

Use a descriptive user agent and respect each court's terms, robots policy, rate limits, and operational constraints.

## CLI

```text
juriscraper list
juriscraper scrape ca1 --pretty
juriscraper scrape ca1 --file saved.html --pretty
juriscraper upstream juriscraper.opinions.united_states.federal_appellate.ca1 --pretty
juriscraper version
```

## Scope of 0.1.0

The framework is implemented natively, but **not every upstream court module has been ported to Ruby yet**. The optional `PythonBridge` is the compatibility path for the upstream corpus. Native ports can be added independently through the registry without changing callers.

## License

BSD-2-Clause. Upstream Juriscraper is also BSD-2-Clause; see `NOTICE` for attribution and non-affiliation.
