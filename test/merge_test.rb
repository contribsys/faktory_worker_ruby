require "helper"

class MergeTest < LiveTest
  class SomeJob
    include Faktory::Job
    faktory_options queue: :some_q, retry: 1, reserve_for: 2, custom: {unique_for: 3}
    def perform(*)
    end
  end

  describe "MergeTest" do
    before do
      require "faktory/testing"
      Faktory::Testing.fake!
    end

    after do
      Faktory::Testing.disable!
      Faktory::Queues.clear_all
    end

    it "does not raise" do
      threads = []
      threads << Thread.new { 10_000.times { SomeJob.perform_async("example-arg") } }
      threads << Thread.new { 10_000.times { SomeJob.perform_async("example-arg") } }
      threads.each(&:join)
      assert_equal 20_000, Faktory::Queues["some_q"].size
      assert_equal 0, Faktory::Queues["default"].size
    end
  end
end
