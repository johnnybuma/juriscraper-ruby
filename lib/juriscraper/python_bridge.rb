# frozen_string_literal: true

require "json"
require "open3"

module Juriscraper
  class PythonBridge
    SCRIPT = <<~'PYTHON'.freeze
      import asyncio
      import importlib
      import inspect
      import json
      import sys

      module_name = sys.argv[1]
      module = importlib.import_module(module_name)
      site = module.Site()

      async def run_site():
          try:
              result = site.parse()
              if inspect.isawaitable(result):
                  await result
              return list(site)
          finally:
              close = getattr(site, "close_session", None)
              if close is not None:
                  result = close()
                  if inspect.isawaitable(result):
                      await result

      payload = asyncio.run(run_site())
      print("__JURISCRAPER_JSON__" + json.dumps(payload, default=str))
    PYTHON

    def initialize(python: ENV.fetch("JURISCRAPER_PYTHON", "python3"))
      @python = python
    end

    def scrape(module_name)
      stdout, stderr, status = Open3.capture3(@python, "-c", SCRIPT, module_name.to_s)
      unless status.success?
        raise UpstreamBridgeError,
              "upstream Juriscraper failed (#{status.exitstatus}): #{stderr.strip.empty? ? stdout.strip : stderr.strip}"
      end

      marker = "__JURISCRAPER_JSON__"
      json = stdout.lines.reverse.find { |line| line.include?(marker) }
      raise UpstreamBridgeError, "upstream did not emit a result payload" unless json

      JSON.parse(json.split(marker, 2).last, symbolize_names: true)
    rescue Errno::ENOENT => e
      raise UpstreamBridgeError, "Python executable #{@python.inspect} was not found: #{e.message}"
    rescue JSON::ParserError => e
      raise UpstreamBridgeError, "upstream returned invalid JSON: #{e.message}"
    end

    def available?
      _stdout, _stderr, status = Open3.capture3(@python, "-c", "import juriscraper")
      status.success?
    rescue Errno::ENOENT
      false
    end
  end
end
