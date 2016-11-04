require "test_helper"

module AdaptivePolling
  class EntryPointTest < TestCase
    should "have a version number" do
      refute_nil ::AdaptivePolling::VERSION
    end
  end
end
