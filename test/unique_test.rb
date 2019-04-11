require 'helper'

class UniqueTest < Minitest::Test

  class LonelyJob
    include Faktory::Job
    faktory_options custom: { unique_for: 10 }
    def perform(*)
    end
  end

  def test_unique_push
    rc = LonelyJob.perform_async(1)
    assert_equal String, rc.class
    assert_equal 24, rc.size

    pro_only do
      # This test will fail if performed against Faktory.
      # It's here to test Faktory Pro.
      rc = LonelyJob.perform_async(1)
      assert_equal Symbol, rc.class
      assert_equal :NOTUNIQUE, rc
    end

    rc = LonelyJob.perform_async(2)
    assert_equal String, rc.class
    assert_equal 24, rc.size
  end
end
