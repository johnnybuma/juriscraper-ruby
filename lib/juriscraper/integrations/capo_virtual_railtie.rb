# frozen_string_literal: true

if defined?(Rails::Railtie)
  module Juriscraper
    module Integrations
      module CapoVirtual
        class Railtie < Rails::Railtie
          config.after_initialize do
            next unless Object.const_defined?(:CaseDocumentAnalysis)
            next unless Object.const_defined?(:CaseStrategy)
            next unless Object.const_defined?(:LegalAuthority)

            Juriscraper::Integrations::CapoVirtual.install!
          end
        end
      end
    end
  end
end
