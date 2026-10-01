# frozen_string_literal: true

require_relative "test_helper"

class PythonBridgeTest < Minitest::Test
  def test_available_returns_boolean
    assert_includes [true, false], Juriscraper::PythonBridge.new.available?
  end
end
