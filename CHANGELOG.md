# Changelog

## 0.1.0 - 2026-10-01

- Initial native Ruby scraping framework.
- Juriscraper-style \`AbstractSite\`, \`OpinionSite\`, \`OpinionSiteLinear\`, and \`OralArgumentSite\` classes.
- Enumerable output, JSON serialization, metadata sanity checks, date sorting, and stable \`snapshot_hash\` (without overriding Ruby \`Object#hash\`).
- Polite \`Net::HTTP\` client with retries, redirects, throttling, and request headers.
- Native First Circuit (\`ca1\`) opinion scraper.
- Registry and command-line interface.
- Optional Python bridge for the complete upstream Juriscraper scraper corpus.
- Local fixture-based tests.
