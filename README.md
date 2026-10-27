# juriscraper-ruby

`juriscraper-ruby` is a Ruby implementation of the core ideas and caller-facing behavior of [Free Law Project's Juriscraper](https://github.com/freelawproject/juriscraper): court-site scrapers with a common lifecycle, normalized metadata, enumerable results, JSON output, document downloading, and reusable opinion/oral-argument base classes.

It has two layers:

1. **Native Ruby framework.** Build and run court scrapers without Python. Native coverage currently includes the First Circuit (`ca1`) plus Ninth Circuit published (`ca9_p`) and unpublished (`ca9_u`) opinion feeds, with the framework needed to port additional courts.
2. **Optional upstream bridge.** If the Python `juriscraper` package is installed, Ruby can invoke any existing upstream scraper module. This provides broad coverage immediately while individual scrapers are migrated to native Ruby.

This project is independent from Free Law Project. See `NOTICE`.

## Requirements

- Ruby **3.1 or newer**, including Ruby 3.3, 3.4, and 4.x. Ruby 3.0 (the default `apt` package on Ubuntu 22.04) is too old and `gem install` will refuse the gem.
- Git, for the Bundler git source.
- A C compiler. Nokogiri 1.19 installs from a precompiled package on current macOS and Linux, but its dependency `racc` builds a small native extension.
- Nokogiri `>= 1.16`, `< 2` (installed automatically).
- Optional: Python 3.10+ in a virtualenv, only if you want the upstream Juriscraper bridge.

This gem is **not published on RubyGems** (`https://rubygems.org/gems/juriscraper-ruby` returns 404). Install it from GitHub. Do not put a bare `gem "juriscraper-ruby"` in a Gemfile.

Do not install with `sudo gem`. On macOS that fights System Integrity Protection, and on Linux it writes into the distro Ruby and breaks the next `apt upgrade`.

## Install Ruby

Check what you already have:

```bash
ruby -v
which ruby
```

You want `ruby 3.1` or newer, and `which ruby` must **not** be `/usr/bin/ruby` on a Mac (that binary is gone or too old). If the version is already new enough, skip to [Install the gem](#install-the-gem).

### macOS — Homebrew (recommended)

Homebrew's Ruby is separate from anything Apple used to ship. Apple Silicon installs under `/opt/homebrew`. Intel Macs install under `/usr/local`.

1. Install the Xcode command line tools (compiler for `racc`) and Homebrew if you do not have them:

```bash
xcode-select --install
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

2. Install Ruby and Git:

```bash
brew install ruby git
```

3. Put Homebrew's Ruby ahead of any system Ruby. Use **one** of these, then open a new terminal.

Apple Silicon (`uname -m` prints `arm64`):

```bash
echo 'export PATH="/opt/homebrew/opt/ruby/bin:$PATH"' >> ~/.zshrc
exec zsh -l
```

Intel (`uname -m` prints `x86_64`):

```bash
echo 'export PATH="/usr/local/opt/ruby/bin:$PATH"' >> ~/.zshrc
exec zsh -l
```

4. Confirm you are not still on a leftover Ruby:

```bash
ruby -v          # 3.1 or newer
which ruby       # .../opt/ruby/bin/ruby, not /usr/bin/ruby
```

### Linux — distro package, when it is new enough

| Distro | Package Ruby | Use it? |
| --- | --- | --- |
| Debian 12 (bookworm) | 3.1.2 | yes |
| Debian 13 (trixie) | 3.3 | yes |
| Ubuntu 24.04 LTS | 3.2 | yes |
| Ubuntu 22.04 LTS | 3.0.2 | **no** — use rbenv below |
| Fedora 40+ | 3.3 | yes |
| Arch / Manjaro | current | yes |

Debian or Ubuntu (24.04 or Debian 12+):

```bash
sudo apt update
sudo apt install -y ruby ruby-dev build-essential git pkg-config
ruby -v
```

`ruby -v` must print 3.1 or newer. If it prints 3.0, stop and use rbenv. Do not try to force the gem onto 3.0.

Fedora / RHEL-family:

```bash
sudo dnf install -y ruby ruby-devel gcc make redhat-rpm-config git pkgconf-pkg-config
ruby -v
```

Arch:

```bash
sudo pacman -S --needed ruby base-devel git pkgconf
ruby -v
```

### macOS or Linux — rbenv, when you need a specific Ruby

Use this on Ubuntu 22.04, or anywhere you want Ruby 3.3 pinned next to an older system Ruby. Same commands on both operating systems after the build dependencies are installed.

Debian / Ubuntu build dependencies:

```bash
sudo apt update
sudo apt install -y git build-essential libssl-dev libreadline-dev zlib1g-dev \
  libyaml-dev libffi-dev pkg-config autoconf bison
```

macOS build dependencies:

```bash
xcode-select --install
brew install openssl@3 readline libyaml autoconf
```

Install rbenv and ruby-build into your home directory (works even when the distro `rbenv` package is stale):

```bash
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
```

macOS uses zsh. Linux desktop installs usually use bash. Add the matching block.

macOS (`~/.zshrc`):

```bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.zshrc
echo 'eval "$(rbenv init - zsh)"' >> ~/.zshrc
exec zsh -l
```

Linux bash (`~/.bashrc`):

```bash
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
exec bash -l
```

Then install Ruby 3.3.11 and make it the default. Compiling takes several minutes.

```bash
rbenv install 3.3.11
rbenv global 3.3.11
ruby -v          # ruby 3.3.11
which ruby       # ~/.rbenv/shims/ruby
gem -v
```

## Install the gem

Pick one. An application should use Bundler. A laptop-wide `juriscraper` command should use the built gem.

### A. Bundler, in a Rails or other app (usual)

The gem is not on RubyGems, so the Gemfile must name the git repository.

```ruby
# Gemfile
source "https://rubygems.org"

gem "juriscraper-ruby", git: "https://github.com/johnnybuma/juriscraper-ruby", branch: "master"
```

```bash
bundle install
bundle exec ruby -e 'require "juriscraper"; puts Juriscraper::VERSION'
bundle exec juriscraper version
```

`bundle exec` is required. Bundler does not put `juriscraper` on your shell `PATH`.

### B. From a clone, for development

```bash
git clone https://github.com/johnnybuma/juriscraper-ruby.git
cd juriscraper-ruby
bundle install
bundle exec rake test
gem build juriscraper-ruby.gemspec
```

`bundle exec rake test` is the fixture suite. It does not hit the network. A good run ends with `0 failures, 0 errors`.

If `gem install` into the Ruby prefix fails with a permission error, use the user install in the next section. Otherwise, when this Ruby is one you installed yourself (Homebrew or rbenv), install into it directly:

```bash
gem install ./juriscraper-ruby-0.3.0.gem
juriscraper version
```

### C. User install, when the Ruby prefix is not writable

This is the path for a distro Ruby (`apt` / `dnf`) installed as root.

```bash
gem install --user-install ./juriscraper-ruby-0.3.0.gem
```

RubyGems prints a warning that the executable directory is not on `PATH`. That directory is **not the same on every machine**:

- `~/.local/share/gem/ruby/3.3.0/bin` when `~/.gem` does not exist (fresh Linux, and current RubyGems)
- `~/.gem/ruby/3.3.0/bin` when `~/.gem` already exists (typical on a Mac that has installed gems before)

Do not hardcode either path. Ask Ruby, and keep the line your shell will re-read:

```bash
ruby -e 'puts File.join(Gem.user_dir, "bin")'
```

macOS zsh:

```bash
echo 'export PATH="$(ruby -e '\''print File.join(Gem.user_dir, "bin")'\'')":$PATH"' >> ~/.zshrc
exec zsh -l
```

Linux bash:

```bash
echo 'export PATH="$(ruby -e '\''print File.join(Gem.user_dir, "bin")'\'')":$PATH"' >> ~/.bashrc
exec bash -l
```

If you only need it in the current terminal:

```bash
export PATH="$(ruby -e 'print File.join(Gem.user_dir, "bin")'):$PATH"
hash -r
command -v juriscraper
juriscraper version
```

`command -v juriscraper` must print a path under your home directory, not "not found".

## Verify the install

These are the checks that were run against version 0.3.0 on Debian 12 with Ruby 3.3.11. The same commands are what you run on macOS. Expected results are in the comments.

```bash
ruby -v
# ruby 3.1.x or newer

juriscraper version
# 0.3.0

juriscraper list
# ca1
# ca9
# ca9_p
# ca9_u
# first_circuit
# ninth_circuit
# ninth_circuit_published
# ninth_circuit_unpublished
# us_ca1

# Offline parse of the fixture shipped in the repository.
# From the clone:
juriscraper scrape ca1 --file test/fixtures/ca1.html --pretty
# JSON array, first case_names == "Smith v. Jones"

ruby -e 'require "juriscraper"; puts Juriscraper::VERSION'
# 0.3.0
```

Inside an app, prefix the `juriscraper` lines with `bundle exec`.

## Optional: upstream Python Juriscraper

Native Ruby scrapers do not need Python. The bridge does. Use a virtualenv on both macOS and Linux. Homebrew Python and Debian/Ubuntu Python reject a system-wide `pip install` with `externally-managed-environment`.

macOS, if `python3` is missing:

```bash
brew install python
```

Debian / Ubuntu:

```bash
sudo apt install -y python3 python3-venv python3-pip
```

Fedora:

```bash
sudo dnf install -y python3
```

Then, same commands on both operating systems:

```bash
python3 -m venv ~/.venvs/juriscraper
~/.venvs/juriscraper/bin/python -m pip install -U pip juriscraper
~/.venvs/juriscraper/bin/python -c 'import juriscraper; print("python juriscraper ok")'
```

Point Ruby at that interpreter. Do not rely on whichever `python3` happens to be first on `PATH`.

```bash
export JURISCRAPER_PYTHON="$HOME/.venvs/juriscraper/bin/python"
```

macOS: append that `export` to `~/.zshrc`. Linux bash: append it to `~/.bashrc`.

Confirm the bridge can see the module (this does not scrape a court):

```bash
ruby -e 'require "juriscraper"; abort "bridge down" unless Juriscraper::PythonBridge.new.available?; puts "python bridge ok"'
```

With Bundler, run that under `bundle exec ruby -e '...'`.

A real upstream scrape (network, and the court site must be up):

```bash
juriscraper upstream juriscraper.opinions.united_states.federal_appellate.ca1 --pretty
```

## CourtListener token

Scraping a saved HTML file does not need a token. Live CourtListener REST calls do.

Create a token at <https://www.courtlistener.com/profile/api/>.

```bash
# macOS
echo 'export COURTLISTENER_TOKEN="paste-the-token-here"' >> ~/.zshrc

# Linux bash
echo 'export COURTLISTENER_TOKEN="paste-the-token-here"' >> ~/.bashrc
```

Open a new shell, then:

```bash
juriscraper courtlistener usage
juriscraper courtlistener search --type opinions --court ca9 --q "spoliation" --pretty
```

The client sends `Authorization: Token <key>`. The word `Token` is required. Details are in [CourtListener API token](#courtlistener-api-token) below.

## If installation fails

**`gem install` says `required_ruby_version` or the gem requires Ruby >= 3.1.**  
`ruby -v` is 3.0 or older. On Ubuntu 22.04 that is the `apt` Ruby. Install 3.3 with rbenv (above) and open a new shell so `which ruby` changes.

**`juriscraper: command not found` after a successful install.**  
The gem binary directory is not on `PATH`. Re-read the warning `gem install` printed, or run `ruby -e 'puts File.join(Gem.user_dir, "bin")'` for a `--user-install`, or `ruby -e 'puts Gem.bindir'` for a normal install. Export that directory and start a new shell.

**`cannot load such file -- nokogiri` or a compile error inside `racc` / `nokogiri`.**  
The C toolchain or XML libraries are missing. Install them and run `gem install` or `bundle install` again.

macOS:

```bash
xcode-select --install
brew install pkg-config libxml2 libxslt
```

Debian / Ubuntu:

```bash
sudo apt install -y build-essential pkg-config libxml2-dev libxslt1-dev zlib1g-dev
```

Fedora:

```bash
sudo dnf install -y gcc make ruby-devel libxml2-devel libxslt-devel zlib-devel
```

A healthy Nokogiri install line looks like `Installing nokogiri-1.19.4 (arm64-darwin)` or `Installing nokogiri-1.19.4 (x86_64-linux-gnu)`, not a long `libxml2` compile.

**`You don't have permission to write` during `gem install`.**  
Do not use `sudo`. Use `gem install --user-install` and the PATH step in section C.

**`externally-managed-environment` from pip.**  
You ran `pip install` against Homebrew or distro Python. Use the virtualenv in the Python section. Do not pass `--break-system-packages`.

**`Could not locate Gemfile` or `juriscraper` works in one directory and not another.**  
An app install is isolated. Run `bundle exec juriscraper ...` from that app. A user-installed CLI is global only after its `bin` directory is on `PATH`.

**Bundler: `Could not find gem 'juriscraper-ruby'`.**  
The Gemfile is missing the `git:` source. The gem is not on RubyGems.

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

## Rails 8 / CapoVirtual integration

Version 0.2.0 includes an optional adapter designed against `capo_virtual/master`. Capo's CaseDocument and CaseStrategy analysis flows already converge on `LegalAuthority.scrape_web!`, persistence, identity gating, and pgvector indexing. The gem integrates at that existing seam instead of creating a parallel authority store.

When loaded inside the CapoVirtual Rails app, the integration auto-installs after Rails initialization when `CaseDocumentAnalysis`, `CaseStrategy`, and `LegalAuthority` are present. On a case-law crawl with a nonblank research query it:

1. scrapes the configured official court feeds (Ninth Circuit published and unpublished by default) and keeps only entries whose case name, docket number, status, or court identifier matches a substantive query term;
2. sends the discovered official opinion PDF URLs through Capo's existing `LegalAuthorityCrawler` with `sites: [:uscourts]`, `max_depth: 0`, and `case_law_only: false`;
3. lets Capo perform PDF extraction, metadata classification, deduplication, `LegalAuthority` persistence, and pgvector indexing;
4. runs Capo's original CourtListener case-law crawl unchanged; and
5. merges the official-court `authority_ids` / `new_authority_ids` into the normal result consumed by both `CaseDocumentAnalysis` and `CaseStrategyPromptConstruct`.

No Capo model is redefined and the gem does not write directly to Capo tables.

Configuration can live in `config/initializers/juriscraper.rb`:

```ruby
Juriscraper::Integrations::CapoVirtual.configure do |config|
  config.enabled = true
  config.court_ids = %w[ca9_p ca9_u]
  config.max_seed_opinions = 8
end
```

Equivalent environment variables:

```text
JURISCRAPER_CAPO_ENABLED=1
JURISCRAPER_CAPO_COURTS=ca9_p,ca9_u
JURISCRAPER_CAPO_MAX_SEEDS=8
```

Set `JURISCRAPER_CAPO_ENABLED=0` to disable the hook completely. The hook is only active for calls using `case_law_only: true` with a nonblank query and without `cde_only: true`; ordinary statute/regulation crawls are untouched. If the original crawl uses `dry_run: true`, the supplemental crawl also uses dry run and does not write authorities or embeddings. Explicit URL exclusions and a positive `max_pages` cap apply to the supplemental pass. A query with no matching feed metadata produces no supplemental ingest; independent feed discovery with `discover(query: nil)` still returns recent entries. Official-court ingestion is best-effort: failure of the supplemental Juriscraper pass is logged but does not replace or suppress Capo's existing CourtListener research.

You can inspect the feed discovery independently:

```ruby
Juriscraper::Integrations::CapoVirtual.discover(
  query: "Ninth Circuit education disability precedent"
)
```

The returned rows contain `court_id`, `case_name`, `docket_number`, `date_filed`, `precedential_status`, and `download_url`.

### Ninth Circuit native scrapers

```ruby
published = Juriscraper.registry.build("ca9_p").parse.to_a
unpublished = Juriscraper.registry.build("ca9_u").parse.to_a

# `ca9` and `ninth_circuit` are aliases for the published feed.
```

## Optional full upstream coverage

Install Python into a virtualenv first. The steps that work on both macOS and Linux are in [Optional: upstream Python Juriscraper](#optional-upstream-python-juriscraper). A bare `pip install juriscraper` fails on Homebrew Python and on Debian/Ubuntu with `externally-managed-environment`.

```bash
export JURISCRAPER_PYTHON="$HOME/.venvs/juriscraper/bin/python"
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

## CourtListener API token

REST calls use [CourtListener API v4](https://www.courtlistener.com/help/api/rest/). Create a token at <https://www.courtlistener.com/profile/api/> and send it as:

```http
Authorization: Token <your-token>
```

The word `Token` is required. A missing prefix is the usual reason a key looks rate-limited: CourtListener records the call as anonymous.

```ruby
require "juriscraper"

Juriscraper.configure do |config|
  config.courtlistener_token = ENV.fetch("COURTLISTENER_TOKEN")
  # optional: config.courtlistener_base = "https://www.courtlistener.com/api/rest/v4"
end

client = Juriscraper::CourtListener::Client.new.require_token!

page = client.search(q: "qualified immunity", type: :opinions, court: "ca9")
page.each { |hit| puts hit["caseName"] }

client.usage
client.docket(123)
client.citation_lookup(text: "410 U.S. 113")
```

`Client.new` with no argument reads, in order:

1. `Juriscraper.configuration.courtlistener_token` when it was set (including `""`, which forces an unauthenticated request);
2. otherwise `ENV["COURTLISTENER_TOKEN"]`.

An explicit `token:` argument wins over both. The value is sent only to the configured API host. `require_token!` raises `Juriscraper::ConfigurationError` when nothing is configured.

Search `type:` accepts `:opinions` (`o`), `:recap` (`r`), `:dockets` (`d`), `:documents` (`rd`), `:people` (`p`), and `:oral_arguments` (`oa`). `court:` may be one id or a list, sent space-separated the way the search API expects.

`citation_lookup` posts form field `text`. `recap_fetch` posts JSON and does not store the PACER password.

HTTP 401/403 raise `Juriscraper::CourtListenerAuthError`. HTTP 429 raises `Juriscraper::CourtListenerRateLimitError` with `retry_after` and is not retried. Authenticated default limits are 5/minute, 50/hour, and 125/day unless a membership raises them.

```bash
export COURTLISTENER_TOKEN=...
juriscraper courtlistener search --type opinions --court ca9 --q "spoliation" --pretty
juriscraper courtlistener get dockets/123 --pretty
juriscraper courtlistener usage
```

`cl` is an alias for `courtlistener`.

When `COURTLISTENER_TOKEN` or `courtlistener_token` is set, the CapoVirtual hook also runs one authenticated opinion search and stores it on `result[:juriscraper][:courtlistener]`. With no token that step is skipped.

## CLI

```text
juriscraper list
juriscraper scrape ca1 --pretty
juriscraper scrape ca1 --file saved.html --pretty
juriscraper upstream juriscraper.opinions.united_states.federal_appellate.ca1 --pretty
juriscraper courtlistener search --type opinions --court ca9 --q "spoliation" --pretty
juriscraper version
```

## Scope

Version 0.3.0 adds the CourtListener REST client. The scraping framework is native, but **not every upstream court module has been ported to Ruby yet**. Native coverage today is the First Circuit and the Ninth Circuit published and unpublished feeds. The optional `PythonBridge` is the compatibility path for the rest of the upstream corpus. Native ports can be added independently through the registry without changing callers.

## License

BSD-2-Clause. Upstream Juriscraper is also BSD-2-Clause; see `NOTICE` for attribution and non-affiliation.
