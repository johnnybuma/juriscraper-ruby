# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "tmpdir"

class DocketsCLITest < Minitest::Test
  class CLI < Juriscraper::CLI
    attr_accessor :fake_fetcher
    private
    def docket_fetcher(_options)
      fake_fetcher
    end
  end

  class Fetcher
    attr_reader :calls, :closed
    def initialize(error: nil)
      @calls, @error = [], error
    end
    def fetch(record, source:, previous: nil)
      @calls << [record, source]
      raise @error if @error
      { "case" => record, "status" => "complete", "sources" => { source => { "docket_entries" => [{ "description" => "one" }] } } }
    end
    def close
      @closed = true
    end
  end

  def test_source_prompt_atomic_output_and_resume
    Dir.mktmpdir do |dir|
      input, output = File.join(dir, "cases.json"), File.join(dir, "reports.json")
      record = { "caseId" => 123, "courtId" => "candc", "caseNumberFull" => "3:2026cv00001", "caseTitle" => "Alpha v. Beta" }
      File.write(input, JSON.generate([record]))
      cli = CLI.new(out: StringIO.new, err: StringIO.new, input: StringIO.new("both\n"))
      fake = Fetcher.new
      cli.fake_fetcher = fake
      assert_equal 0, cli.run(["dockets", input, "--output", output])
      assert_equal "both", fake.calls.first[1]
      assert_equal "complete", JSON.parse(File.read(output))["cases"][0]["status"]
      assert fake.closed
      assert_equal 0, cli.run(["dockets", input, "--source", "both", "--output", output])
      assert_equal 1, fake.calls.length
      assert_equal 0, cli.run(["dockets", input, "--source", "both", "--output", output, "--refresh"])
      assert_equal 2, fake.calls.length
      assert_equal 1, cli.run(["dockets", input, "--source", "pacer", "--output", output])
      assert_equal 2, fake.calls.length
    end
  end

  def test_failed_cases_are_checkpointed_and_retried
    Dir.mktmpdir do |dir|
      input, output = File.join(dir, "cases.json"), File.join(dir, "reports.json")
      File.write(input, JSON.generate([{ "caseId" => 123, "courtId" => "candc", "caseNumberFull" => "3:2026cv00001", "caseTitle" => "Alpha v. Beta" }]))
      cli = CLI.new(out: StringIO.new, err: StringIO.new, input: StringIO.new)
      cli.fake_fetcher = Fetcher.new(error: Juriscraper::AmbiguousDocketError.new("multiple", candidates: [{ "id" => 1 }]))
      assert_equal 1, cli.run(["dockets", input, "--source", "courtlistener", "--output", output])
      saved = JSON.parse(File.read(output))["cases"].first
      assert_equal "error", saved["status"]
      assert_equal [{ "id" => 1 }], saved["candidates"]
      cli.fake_fetcher = Fetcher.new
      assert_equal 0, cli.run(["dockets", input, "--source", "courtlistener", "--output", output])
      assert_equal 1, cli.fake_fetcher.calls.length
    end
  end
end
