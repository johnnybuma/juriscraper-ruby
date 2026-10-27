# frozen_string_literal: true

require "json"
require "optparse"

module Juriscraper
  class CLI
    def self.start(argv = ARGV, out: $stdout, err: $stderr)
      new(out: out, err: err).run(argv)
    end

    def initialize(out:, err:)
      @out = out
      @err = err
    end

    def run(argv)
      command = argv.shift
      case command
      when "list"
        @out.puts Juriscraper.registry.ids
        0
      when "scrape"
        scrape(argv)
      when "upstream"
        upstream(argv)
      when "courtlistener", "cl"
        courtlistener(argv)
      when "version", "--version", "-v"
        @out.puts Juriscraper::VERSION
        0
      else
        @err.puts usage
        command.nil? ? 0 : 64
      end
    rescue Juriscraper::Error, OptionParser::ParseError => e
      @err.puts "juriscraper: #{e.message}"
      1
    end

    private

    def scrape(argv)
      options = { pretty: false, file: nil }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper scrape SCRAPER [options]"
        opts.on("--file PATH", "Parse a saved HTML file instead of making a network request") { |v| options[:file] = v }
        opts.on("--pretty", "Pretty-print JSON") { options[:pretty] = true }
      end
      parser.parse!(argv)
      id = argv.shift or raise OptionParser::MissingArgument, "SCRAPER"
      raise OptionParser::InvalidArgument, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?

      content = options[:file] ? File.binread(options[:file]) : nil
      site = Juriscraper.registry.build(id, content: content).parse
      emit(site.to_a, pretty: options[:pretty])
      0
    end

    def upstream(argv)
      options = { pretty: false, python: ENV.fetch("JURISCRAPER_PYTHON", "python3") }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper upstream PYTHON_MODULE [options]"
        opts.on("--python PATH", "Python executable") { |v| options[:python] = v }
        opts.on("--pretty", "Pretty-print JSON") { options[:pretty] = true }
      end
      parser.parse!(argv)
      mod = argv.shift or raise OptionParser::MissingArgument, "PYTHON_MODULE"
      bridge = PythonBridge.new(python: options[:python])
      emit(bridge.scrape(mod), pretty: options[:pretty])
      0
    end

    def courtlistener(argv)
      sub = argv.shift
      case sub
      when "search" then courtlistener_search(argv)
      when "usage" then courtlistener_usage_cmd(argv)
      when "get" then courtlistener_get(argv)
      else
        @err.puts courtlistener_usage
        sub.nil? ? 0 : 64
      end
    end

    def courtlistener_search(argv)
      options = { pretty: false, type: "opinions", court: nil, q: nil, order_by: "score desc" }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper courtlistener search [options]"
        opts.on("--q QUERY", "Search query") { |v| options[:q] = v }
        opts.on("--type TYPE", "opinions, recap, dockets, documents, people, oral_arguments (or o/r/d/rd/p/oa)") do |v|
          options[:type] = v
        end
        opts.on("--court ID", "CourtListener court id, repeatable via a comma list") { |v| options[:court] = v }
        opts.on("--order-by FIELD", "Default: score desc") { |v| options[:order_by] = v }
        opts.on("--pretty", "Pretty-print JSON") { options[:pretty] = true }
      end
      parser.parse!(argv)
      raise OptionParser::InvalidArgument, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?

      courts = options[:court]&.split(",")&.map(&:strip)
      page = courtlistener_client.search(
        q: options[:q],
        type: options[:type],
        court: courts,
        order_by: options[:order_by]
      )
      emit({ count: page.count, next: page.next_url, results: page.results }, pretty: options[:pretty])
      0
    end

    def courtlistener_usage_cmd(argv)
      options = { pretty: false }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper courtlistener usage [options]"
        opts.on("--pretty", "Pretty-print JSON") { options[:pretty] = true }
      end
      parser.parse!(argv)
      emit(courtlistener_client.usage, pretty: options[:pretty])
      0
    end

    def courtlistener_get(argv)
      options = { pretty: false, params: {} }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper courtlistener get RESOURCE [options]"
        opts.on("--param KEY=VALUE", "Query parameter (repeatable)") do |v|
          key, value = v.split("=", 2)
          raise OptionParser::InvalidArgument, "--param expects KEY=VALUE" if key.to_s.empty? || value.nil?

          options[:params][key] = value
        end
        opts.on("--pretty", "Pretty-print JSON") { options[:pretty] = true }
      end
      parser.parse!(argv)
      resource = argv.shift or raise OptionParser::MissingArgument, "RESOURCE"
      raise OptionParser::InvalidArgument, "unexpected arguments: #{argv.join(' ')}" unless argv.empty?

      payload = courtlistener_client.get(resource, options[:params])
      emit(payload.is_a?(CourtListener::Page) ? { count: payload.count, next: payload.next_url, results: payload.results } : payload,
           pretty: options[:pretty])
      0
    end

    def courtlistener_client
      Juriscraper::CourtListener::Client.new.require_token!
    end

    def courtlistener_usage
      <<~TEXT
        Usage: juriscraper courtlistener COMMAND [options]

        Commands:
          search [options]     Search CourtListener (requires COURTLISTENER_TOKEN)
          get RESOURCE         GET a REST resource, e.g. dockets/123 or opinions
          usage                Show API quota usage for the token

        Auth header: Authorization: Token <COURTLISTENER_TOKEN>
      TEXT
    end

    def emit(value, pretty:)
      @out.puts(pretty ? JSON.pretty_generate(value) : JSON.generate(value))
    end

    def usage
      <<~TEXT
        Usage: juriscraper COMMAND [options]

        Commands:
          list                         List native Ruby scrapers
          scrape SCRAPER [options]     Run a native Ruby scraper
          upstream MODULE [options]    Run any installed Python Juriscraper module
          courtlistener COMMAND        CourtListener REST v4 (Token auth)
          version                      Print gem version
      TEXT
    end
  end
end
