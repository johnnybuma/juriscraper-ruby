# frozen_string_literal: true

module Juriscraper
  class OpinionSiteLinear < OpinionSite
    FIELD_MAP = {
      adversary_numbers: :adversary_number,
      causes: :cause,
      dispositions: :disposition,
      divisions: :division,
      docket_attachment_numbers: :docket_attachment_number,
      docket_document_numbers: :docket_document_number,
      docket_numbers: :docket,
      judges: :judge,
      lower_courts: :lower_court,
      lower_court_ids: :lower_court_id,
      lower_court_judges: :lower_court_judge,
      lower_court_numbers: :lower_court_number,
      nature_of_suit: :nature_of_suit,
      citations: :citation,
      parallel_citations: :parallel_citation,
      summaries: :summary,
      child_courts: :child_court,
      authors: :author,
      joined_by: :joined_by,
      per_curiam: :per_curiam,
      types: :type,
      other_dates: :other_date,
      attorneys: :attorney,
      headnotes: :headnote,
      content: :content
    }.freeze

    attr_reader :cases

    def initialize(**kwargs)
      super
      @cases = []
    end

    protected

    def process_html
      raise NotImplementedError, "#{self.class} must implement #process_html"
    end

    def get_case_names
      cases.map { |item| fetch_case(item, :name) }
    end

    def get_download_urls
      cases.map { |item| absolutize(fetch_case(item, :url)) }
    end

    def get_case_dates
      cases.map { |item| Utils::DateUtils.parse(fetch_case(item, :date)) }
    end

    def get_date_filed_is_approximate
      cases.map { |item| item.fetch(:date_filed_is_approximate, false) }
    end

    def get_precedential_statuses
      if cases.all? { |item| item.key?(:status) }
        cases.map { |item| item[:status] }
      elsif status
        [status] * cases.length
      else
        raise SanityError, "#{self.class}: define per-case :status or site #status"
      end
    end

    FIELD_MAP.each do |attribute, key|
      define_method("get_#{attribute}") do
        next nil if cases.empty? || cases.none? { |item| item.key?(key) }

        cases.map { |item| item[key] }
      end
    end

    private

    def fetch_case(item, key)
      item.fetch(key) { raise ParsingError, "#{self.class}: case is missing #{key.inspect}: #{item.inspect}" }
    end

    def absolutize(value)
      URI.join(url.to_s, value.to_s).to_s
    rescue URI::InvalidURIError
      value.to_s
    end
  end
end
