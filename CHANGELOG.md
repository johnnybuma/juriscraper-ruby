# Changelog

## 0.4.0 - 2026-10-27

- Added native `Pacer::Client`: PACER_USER/PACER_PASS authentication, MFA code/callback/TOTP, client codes, session rotation/logout, paginated PCL case search, and district/bankruptcy HTML docket reports. No filing downloads in this workflow.
- Added CourtListener `find_docket` and `docket_report`: search by PACER case ID, inspect all candidates, require normalized number/title/court/ID matches, reject ambiguity, fetch every entry cursor, and verify entry counts.
- Removed the implicit three-page `Page#each_result` limit; explicit `max_pages:` remains supported. Repeated cursors and malformed pagination raise errors.
- Added `Dockets::Input`, `Dockets::Fetcher`, and `juriscraper dockets`: source selection, no-results fallback, independent both-source reports, preserved export rows, atomic JSON checkpoints, and resume/refresh.
- Added COURTLISTENER_API_KEY alias, corrected API usage endpoint, redacted credential inspection/errors, and rejected cross-origin redirects rather than forwarding POST bodies.
- Added offline regression coverage for identity checks, pagination, fallback, MFA, PACER layouts, protocol restrictions, and CLI resume; CI covers Ruby 3.1, 3.4, and 4.0. Declared the logger runtime dependency for Ruby 4.0/Bundler compatibility.

## 0.3.0 - 2026-10-07

- Added `Juriscraper::CourtListener::Client`, a REST v4 client that sends `Authorization: Token <key>`.
- Token resolution order: explicit argument, `Juriscraper.configuration.courtlistener_token`, then `COURTLISTENER_TOKEN`.
- The token is attached only to the configured CourtListener host. Redirects off that host drop the header.
- Added CLI commands: `juriscraper courtlistener search|get|usage` (alias `cl`).
- CapoVirtual attaches one authenticated opinion search to case-law research when a token is configured. No token leaves the existing crawl unchanged.
- Auth failures raise `CourtListenerAuthError`. HTTP 429 raises `CourtListenerRateLimitError` and includes `Retry-After`. 429 is not retried.

## 0.2.0 - 2026-10-01

- Added native Ninth Circuit published (`ca9_p`) and unpublished (`ca9_u`) RSS opinion scrapers using the court's current `/decisions/` feeds.
- Added `Juriscraper::Integrations::CapoVirtual`, designed against `capo_virtual/master`'s `CaseDocumentAnalysis`, `CaseStrategyPromptConstruct`, `LegalAuthorityOnDemandResearcher`, and `LegalAuthorityCrawler` contracts.
- Capo integration transparently augments `LegalAuthority.scrape_web!(..., case_law_only: true)` with recent official-court opinion URLs, persists them through Capo's existing crawler/indexer, and merges resulting authority IDs into the existing CourtListener result.
- Added Rails auto-install support when `CaseDocumentAnalysis`, `CaseStrategy`, and `LegalAuthority` are present.
- Added environment/configuration controls for Capo integration and seed volume.
- Added CA9 and Capo adapter tests and example configuration.

## 0.1.0 - 2026-10-01

- Initial native Ruby scraping framework.
- Juriscraper-style `AbstractSite`, `OpinionSite`, `OpinionSiteLinear`, and `OralArgumentSite` classes.
- Enumerable output, JSON serialization, metadata sanity checks, date sorting, and stable `snapshot_hash` (without overriding Ruby `Object#hash`).
- Polite `Net::HTTP` client with retries, redirects, throttling, and request headers.
- Native First Circuit (`ca1`) opinion scraper.
- Registry and command-line interface.
- Optional Python bridge for the complete upstream Juriscraper scraper corpus.
- Local fixture-based tests.
