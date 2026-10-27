# frozen_string_literal: true

require "json"
require "optparse"
require "io/console"
require "fileutils"
require "tempfile"

module Juriscraper
  class CLI
    def self.start(argv = ARGV, out: $stdout, err: $stderr, input: $stdin)
      new(out: out, err: err, input: input).run(argv)
    end

    def initialize(out:, err:, input: $stdin)
      @out = out
      @err = err
      @input = input
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
      when "dockets"
        dockets(argv)
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

    def dockets(argv)
      options = { source: nil, output: "docket-reports.json", refresh: false, mfa: true }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: juriscraper dockets INPUT.json [MORE.json ...] [options]"
        opts.on("--source SOURCE", %w[pacer courtlistener both], "pacer, courtlistener, or both (otherwise prompt)") { |v| options[:source] = v }
        opts.on("--output PATH", "Nested JSON output; saved after every case") { |v| options[:output] = v }
        opts.on("--refresh", "Fetch cases already completed in this output") { options[:refresh] = true }
        opts.on("--no-mfa", "Skip interactive MFA prompt (environment OTP/TOTP still works)") { options[:mfa] = false }
      end
      parser.parse!(argv)
      raise OptionParser::MissingArgument, "INPUT.json" if argv.empty?
      records = Dockets::Input.read(argv)
      raise ConfigurationError, "input contains no cases" if records.empty?
      source = options[:source] || prompt_source
      path = File.expand_path(options[:output])
      if argv.any? { |input| File.expand_path(input) == path }
        raise ConfigurationError, "output must differ from the input files"
      end
      state = { "schema_version" => 1, "selected_source" => source, "cases" => [] }
      unless options[:refresh] || !File.exist?(path)
        begin
          state = JSON.parse(File.read(path))
        rescue JSON::ParserError
          raise ConfigurationError, "output is not valid JSON; choose another output path"
        end
        unless state.is_a?(Hash) && state["schema_version"] == 1 && state["cases"].is_a?(Array) && state["selected_source"] == source &&
               state["cases"].all? { |item| item.is_a?(Hash) && item["case"].is_a?(Hash) }
          raise ConfigurationError, "output is incompatible or uses a different source; choose another output path"
        end
      end
      fetcher = docket_fetcher(options)
      failures = 0
      records.each_with_index do |record, index|
        key = docket_key(record)
        position = state["cases"].index { |item| docket_key(item.fetch("case")) == key }
        existing = position && state["cases"][position]
        if existing && existing["status"] == "complete"
          existing["case"] = record # keep every current input row/attorney association
          @err.puts "[#{index + 1}/#{records.length}] #{record['caseNumberFull'] || record['docket_number']}: resumed"
          next
        end
        @err.puts "[#{index + 1}/#{records.length}] #{record['caseNumberFull'] || record['docket_number']}"
        begin
          result = fetcher.fetch(record, source: source, previous: existing)
          failures += 1 if %w[partial error].include?(result["status"])
        rescue Juriscraper::Error => e
          result = { "case" => record, "status" => "error", "error_class" => e.class.name, "message" => e.message }
          result["candidates"] = e.candidates if e.respond_to?(:candidates)
          failures += 1
          @err.puts "  #{e.class}: #{e.message}"
        end
        position ? state["cases"][position] = result : state["cases"] << result
        save_dockets(path, state)
      end
      save_dockets(path, state)
      @out.puts path
      failures.zero? ? 0 : 1
    rescue Interrupt
      save_dockets(path, state) if path && state
      @err.puts "Interrupted; progress saved to #{path}"
      130
    rescue SystemCallError => e
      raise ConfigurationError, "docket file operation failed: #{e.message}"
    ensure
      begin
        fetcher&.close
      rescue Juriscraper::Error => e
        @err.puts "PACER logout failed: #{e.message}"
      end
    end

    def docket_fetcher(options)
      callback = options[:mfa] ? method(:prompt_otp) : nil
      Dockets::Fetcher.new(otp_provider: callback)
    end

    def prompt_source
      @err.print "Docket source [pacer/courtlistener/both]: "
      source = @input.gets.to_s.strip.downcase
      source = { "1" => "pacer", "2" => "courtlistener", "3" => "both" }.fetch(source, source)
      raise ConfigurationError, "select pacer, courtlistener, or both, or pass --source" unless Dockets::Fetcher::SOURCES.map(&:to_s).include?(source)
      source
    end

    def prompt_otp
      @err.print "Current PACER MFA code (blank if MFA is disabled): "
      value = @input.tty? ? @input.noecho(&:gets) : @input.gets
      @err.puts if @input.tty?
      value.to_s.strip
    end

    def docket_key(record)
      identity = Dockets::Identity.new(record)
      [identity.court, identity.case_id, identity.number, Dockets::Identity.normalize_title(identity.title)]
    end

    def save_dockets(path, state)
      FileUtils.mkdir_p(File.dirname(path))
      Tempfile.create(["docket-reports", ".json"], File.dirname(path)) do |file|
        file.write(JSON.pretty_generate(state))
        file.write("\n")
        file.flush
        file.fsync
        File.rename(file.path, path)
      end
    end

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
          dockets INPUT.json [...]     PACER/CourtListener docket entry reports
          version                      Print gem version
      TEXT
    end
  end
end
