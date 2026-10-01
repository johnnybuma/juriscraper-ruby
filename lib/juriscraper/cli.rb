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
          version                      Print gem version
      TEXT
    end
  end
end
