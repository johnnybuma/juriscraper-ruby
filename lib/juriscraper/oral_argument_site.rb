# frozen_string_literal: true

module Juriscraper
  class OralArgumentSite < AbstractSite
    OPTIONAL_ATTRIBUTES = %i[docket_numbers judges case_name_shorts attorneys].freeze
    REQUIRED_ATTRIBUTES = %i[case_dates case_names download_urls blocked_statuses].freeze

    attr_reader(*REQUIRED_ATTRIBUTES, *OPTIONAL_ATTRIBUTES)

    def initialize(**kwargs)
      super
      self.expected_content_types = ["audio/mpeg"]
      configure_attributes(required: REQUIRED_ATTRIBUTES, optional: OPTIONAL_ATTRIBUTES)
    end

    protected

    def get_download_urls = required_implementation!(:get_download_urls)
    def get_case_dates = required_implementation!(:get_case_dates)
    def get_case_names = required_implementation!(:get_case_names)
    def get_docket_numbers = nil
    def get_judges = nil
    def get_attorneys = nil

    private

    def required_implementation!(method)
      raise NotImplementedError, "#{self.class} must implement ##{method}"
    end
  end
end
