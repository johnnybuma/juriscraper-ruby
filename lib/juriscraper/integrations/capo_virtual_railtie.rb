# frozen_string_literal: true

if defined?(Rails::Railtie)
  module Juriscraper
    module Integrations
      module CapoVirtual
        class Railtie < Rails::Railtie
          config.to_prepare do
            case_document_analysis = "CaseDocumentAnalysis".safe_constantize
            case_strategy = "CaseStrategy".safe_constantize
            legal_authority = "LegalAuthority".safe_constantize
            next unless case_document_analysis && case_strategy && legal_authority

            Juriscraper::Integrations::CapoVirtual.install!(legal_authority_class: legal_authority)
          end
        end
      end
    end
  end
end
