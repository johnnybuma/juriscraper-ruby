# frozen_string_literal: true

require "digest/sha1"
require "json"
require "nokogiri"
require "uri"

module Juriscraper
  class AbstractSite
    include Enumerable

    attr_accessor :court_id, :url, :method, :parameters, :status, :should_have_results,
                  :expected_content_types, :request_headers, :cookies
    attr_reader :snapshot_hash, :html, :response, :required_attributes, :optional_attributes, :all_attributes

    def initialize(content: nil, http_client: nil, user_agent: nil, **_kwargs)
      @http_client = http_client || HTTP::Client.new
      @method = "GET"
      @parameters = {}
      @request_headers = {}
      @request_headers["User-Agent"] = user_agent if user_agent
      @cookies = {}
      @should_have_results = false
      @expected_content_types = []
      @court_id = nil
      @url = nil
      @status = nil
      @required_attributes = []
      @optional_attributes = []
      @all_attributes = []
      @raw_content = content
      @downloader_executed = !content.nil?
    end

    def parse
      source = @raw_content || download.body
      @html = make_html_tree(source)
      process_html

      all_attributes.each do |attribute|
        value = send("get_#{attribute}")
        instance_variable_set("@#{attribute}", value)
      end

      clean_attributes!
      @case_name_shorts = get_case_name_shorts if all_attributes.include?(:case_name_shorts)
      post_parse
      check_sanity!
      date_sort!
      @snapshot_hash = Digest::SHA1.hexdigest(Array(@case_names).inspect)
      self
    end

    def each
      return enum_for(:each) unless block_given?

      size.times { |index| yield make_item(index) }
    end

    def [](index)
      make_item(index)
    end

    def size
      Array(@case_names).size
    end
    alias length size

    def empty?
      size.zero?
    end

    def to_a
      each.to_a
    end

    def to_json(*args)
      JSON.generate(json_ready(to_a), *args)
    end

    def to_s
      "#<#{self.class} court_id=#{court_id.inspect} url=#{url.inspect} items=#{size} snapshot_hash=#{snapshot_hash.inspect}>"
    end

    def download
      raise ConfigurationError, "site URL is not configured" if url.to_s.empty?

      @downloader_executed = true
      @response = case method.to_s.upcase
                  when "GET"
                    @http_client.get(url, headers: request_headers, params: parameters)
                  when "POST"
                    @http_client.post(url, headers: request_headers, params: parameters)
                  else
                    raise ConfigurationError, "unsupported HTTP method #{method.inspect}"
                  end
    end

    def download_content(download_url)
      raise DownloadError, "download URL is blank" if download_url.to_s.strip.empty?

      response = @http_client.get(download_url, headers: request_headers)
      raise EmptyFileError, "empty download from #{download_url}" if response.body.empty?

      unless expected_content_types.empty?
        actual = response.content_type
        valid = expected_content_types.any? { |expected| content_type_matches?(actual, expected) }
        unless valid
          raise UnexpectedContentTypeError,
                "expected #{expected_content_types.join(', ')}, got #{actual || 'unknown'} from #{download_url}"
        end
      end

      cleanup_content(response.body)
    end

    def cleanup_content(content)
      content
    end

    def extract_from_text(_scraped_text)
      {}
    end

    protected

    def configure_attributes(required:, optional:)
      @required_attributes = required.map(&:to_sym).freeze
      @optional_attributes = optional.map(&:to_sym).freeze
      @all_attributes = (@required_attributes + @optional_attributes).freeze
      @all_attributes.each { |attribute| instance_variable_set("@#{attribute}", nil) }
    end

    def process_html; end

    def post_parse; end

    def make_html_tree(content)
      Nokogiri::HTML(content.to_s, url)
    end

    def get_blocked_statuses
      [false] * Array(@case_names).length
    end

    def get_case_name_shorts
      Array(@case_names).map { |name| Utils::StringUtils.short_case_name(name) }
    end

    def optional_attribute
      nil
    end

    private

    def make_item(index)
      all_attributes.each_with_object({}) do |attribute, item|
        values = instance_variable_get("@#{attribute}")
        item[attribute] = values[index] if values
      end
    end

    def clean_attributes!
      all_attributes.each do |attribute|
        values = instance_variable_get("@#{attribute}")
        next if values.nil?

        cleaned = values.map { |value| clean_attribute(attribute, value) }
        instance_variable_set("@#{attribute}", cleaned)
      end
    end

    def clean_attribute(attribute, value)
      return value if attribute == :content
      return value if value.nil? || value == true || value == false || value.is_a?(Numeric) || value.is_a?(Date)
      return value.map { |v| clean_attribute(attribute, v) } if value.is_a?(Array)
      return value.transform_values { |v| clean_attribute(attribute, v) } if value.is_a?(Hash)

      text = Utils::StringUtils.harmonize(value)
      if attribute == :case_dates || attribute == :other_dates
        Utils::DateUtils.parse(text)
      else
        text
      end
    end

    def check_sanity!
      lengths = all_attributes.each_with_object({}) do |attribute, memo|
        values = instance_variable_get("@#{attribute}")
        memo[attribute] = values.length if values.is_a?(Array)
      end

      if lengths.values.uniq.length > 1
        raise SanityError, "#{court_id}: metadata fields have differing lengths: #{lengths.inspect}"
      end

      missing = required_attributes.select { |attribute| instance_variable_get("@#{attribute}").nil? }
      raise SanityError, "#{court_id}: missing required metadata: #{missing.join(', ')}" unless missing.empty?

      if Array(@case_names).empty?
        message = "#{court_id}: returned zero items"
        should_have_results ? raise(SanityError, message) : Juriscraper.configuration.logger.warn(message)
        return
      end

      Array(@case_names).each do |name|
        raise SanityError, "#{court_id}: blank case name" if name.to_s.strip.empty?
      end

      Array(@case_dates).each do |date|
        raise SanityError, "#{court_id}: case date is not a Date: #{date.inspect}" unless date.is_a?(Date)
        raise SanityError, "#{court_id}: implausible case date #{date}" if date.year > 2100
      end
    end

    def date_sort!
      return if size < 2

      indices = (0...size).sort_by do |index|
        [@case_dates[index] || Date.new(1, 1, 1), @case_names[index].to_s]
      end.reverse

      all_attributes.each do |attribute|
        values = instance_variable_get("@#{attribute}")
        next unless values.is_a?(Array)

        instance_variable_set("@#{attribute}", indices.map { |index| values[index] })
      end
    end

    def json_ready(value)
      case value
      when Date, Time, DateTime
        value.iso8601
      when Array
        value.map { |item| json_ready(item) }
      when Hash
        value.transform_values { |item| json_ready(item) }
      else
        value
      end
    end

    def content_type_matches?(actual, expected)
      return false if actual.nil?
      return true if actual == expected.downcase

      expected == "application/pdf" && actual == "application/octet-stream"
    end
  end
end
