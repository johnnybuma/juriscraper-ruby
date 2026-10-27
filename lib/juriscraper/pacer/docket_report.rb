# frozen_string_literal: true

require "date"
require "nokogiri"

module Juriscraper
  module Pacer
    class DocketReport
      def parse(html, identity:)
        doc = Nokogiri::HTML(html)
        doc.css("script,style").remove
        text = doc.text
        if text.match?(/Case not found\.|There are no documents in this case|There are proceedings.*none satisfy the selection criteria/im)
          raise DocketNotFoundError, "PACER returned no docket results"
        end
        if doc.at_css('input[name="loginId"], input[name="password"]')
          raise PacerAuthError, "PACER returned a login page"
        end
        number = text[/DOCKET FOR CASE\s*#?\s*:\s*([^\s]+)/i, 1] ||
                 text[/(?:Bankruptcy Petition|Adversary Proceeding)\s*#?\s*:\s*([^\s]+)/i, 1]
        raise ParsingError, "PACER report header did not identify the expected case number" unless identity.number_matches?(number)

        title = extract_title(doc)
        if title && !identity.title_matches?(title)
          raise ParsingError, "PACER report title does not match the supplied case title"
        end
        tables = doc.xpath("//table")
        first = tables.find { |table| direct_rows(table).any? { |row| row.xpath("./td|./th").any? { |cell| cell.text.strip == "Docket Text" } } }
        raise ParsingError, "PACER response has no recognized Docket Text table" unless first
        multi_document = direct_rows(first).any? { |row| row.xpath("./td|./th")[2]&.text.to_s.match?(/Select.*all/m) }
        report_tables = [first] + first.xpath("following-sibling::table").to_a
        entries = []
        report_tables.each do |table|
          next if table.text.match?(/Transaction Receipt|PACER Service Center|Total\s+file\s*size\s+of\s+selected\s+documents|Footer format:/i)
          direct_rows(table).each do |row|
            cells = row.xpath("./td").to_a
            next if cells.empty? || cells.any? { |cell| cell.text.strip == "Docket Text" }
            if cells.length == 4
              # Multiple-document mode adds a selection column and attachment
              # controls. Neither is a docket entry or filing to retrieve.
              next if cells[0..2].all? { |cell| cell.text.strip.empty? } && cells[3].at_css('table input[name^="document_"]')
              if multi_document || cells[2].at_css('input[name="all_documents"]')
                cells = [cells[0], cells[1], cells[3]]
              elsif identity.court.end_with?("b")
                cells = [cells[0], cells[2], cells[3]]
              end
            end
            next if cells.all? { |cell| cell.text.strip.empty? }
            raise ParsingError, "unrecognized PACER docket row (#{cells.length} columns)" unless cells.length == 3
            raw_date, raw_number, description = cells.map { |cell| text_with_breaks(cell).strip }
            entries << {
              "report_sequence" => entries.length + 1,
              "entry_number" => raw_number[/\A\d+/]&.to_i,
              "entry_number_text" => raw_number.empty? ? nil : raw_number,
              "date_filed" => parse_date(raw_date), "date_filed_text" => raw_date.empty? ? nil : raw_date,
              "date_entered" => parse_date(description[/Entered:\s*(\d{1,2}\/\d{1,2}\/\d{4})/i, 1]),
              "description" => description
            }
          end
        end
        { "source" => "pacer", "metadata" => { "docket_number" => number, "case_name" => title,
          "court_id" => identity.court, "pacer_case_id" => identity.case_id,
          "case_name_verified" => !title.nil? }, "docket_entries" => entries, "entry_count" => entries.length }
      end

      private

      def direct_rows(table)
        table.xpath("./tr|./tbody/tr")
      end

      def text_with_breaks(node)
        copy = node.dup
        copy.css("br").each { |br| br.replace("\n") }
        copy.text
      end

      def extract_title(doc)
        doc.xpath("//td").each do |cell|
          lines = text_with_breaks(cell).lines.map(&:strip).reject(&:empty?)
          next unless lines.any? { |line| line.match?(/\A(?:Assigned to|Referred to|Cause):/) }
          title = lines.take_while { |line| !line.match?(/\A(?:Assigned to|Referred to|Cause):/) }.join(" ")
          return title unless title.empty? || title.match?(/\A(?:Date|Chapter|Voluntary|Asset)/)
        end
        nil
      end

      def parse_date(value)
        return nil if value.to_s.strip.empty?
        text = value.strip
        format = case text
                 when /\A\d{1,2}\/\d{1,2}\/\d{4}\z/ then "%m/%d/%Y"
                 when /\A\d{1,2}\/\d{1,2}\/\d{2}\z/ then "%m/%d/%y"
                 when /\A\d{4}-\d{2}-\d{2}\z/ then "%Y-%m-%d"
                 end
        format && Date.strptime(text, format).iso8601
      rescue Date::Error
        nil
      end
    end
  end
end
