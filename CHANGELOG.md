# Changelog

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
