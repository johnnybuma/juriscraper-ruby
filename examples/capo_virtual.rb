# frozen_string_literal: true

require "juriscraper"

Juriscraper::Integrations::CapoVirtual.configure do |config|
  config.enabled = true
  config.court_ids = %w[ca9_p ca9_u]
  config.max_seed_opinions = 8
end

# In capo_virtual this is installed automatically after Rails initializes.
Juriscraper::Integrations::CapoVirtual.install!

# Existing CaseDocumentAnalysis / CaseStrategy code can keep calling:
# LegalAuthority.scrape_web!(..., case_law_only: true)
#
# The adapter adds recent official Ninth Circuit opinion PDF URLs as a separate
# uscourts.gov ingest, then merges the resulting LegalAuthority IDs into the
# existing CourtListener crawl result used by both analysis workflows.
