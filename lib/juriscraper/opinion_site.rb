# frozen_string_literal: true

module Juriscraper
  class OpinionSite < AbstractSite
    OPTIONAL_ATTRIBUTES = %i[
      adversary_numbers causes dispositions divisions docket_attachment_numbers
      docket_document_numbers docket_numbers judges lower_courts lower_court_ids
      lower_court_judges lower_court_numbers nature_of_suit citations
      parallel_citations summaries case_name_shorts child_courts authors joined_by
      per_curiam types other_dates attorneys headnotes content
    ].freeze

    REQUIRED_ATTRIBUTES = %i[
      case_dates case_names download_urls precedential_statuses blocked_statuses
      date_filed_is_approximate
    ].freeze

    attr_reader(*REQUIRED_ATTRIBUTES, *OPTIONAL_ATTRIBUTES)

    def initialize(**kwargs)
      super
      self.expected_content_types = ["application/pdf"]
      configure_attributes(required: REQUIRED_ATTRIBUTES, optional: OPTIONAL_ATTRIBUTES)
    end

    protected

    def get_download_urls = required_implementation!(:get_download_urls)
    def get_case_dates = required_implementation!(:get_case_dates)
    def get_case_names = required_implementation!(:get_case_names)
    def get_precedential_statuses = required_implementation!(:get_precedential_statuses)
    def get_date_filed_is_approximate = [false] * Array(@case_names).length

    OPTIONAL_ATTRIBUTES.each do |attribute|
      define_method("get_#{attribute}") { nil } unless method_defined?("get_#{attribute}")
    end

    private

    def required_implementation!(method)
      raise NotImplementedError, "#{self.class} must implement ##{method}"
    end
  end
end
