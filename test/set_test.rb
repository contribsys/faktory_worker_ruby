require 'helper'

class SetTest < LiveTest

  class SomeJob
    include Faktory::Job
    faktory_options retry: 1, reserve_for: 2, custom: { unique_for: 3 }
    def perform(*)
    end
  end

  describe 'Faktory::Job.set' do
    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
    end

    after do
      Faktory::Testing.disable!
      Faktory::Queues.clear_all
    end

    it 'overrides faktory_options' do
      SomeJob.set(queue: 'some_q').perform_async('example-arg')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].last
      assert_equal 1, job['retry']
      assert_equal 2, job['reserve_for']
      assert_equal 3, job['custom']['unique_for']
    end

    it 'overrides faktory_options on the instance' do
      SomeJob.set(queue: 'some_q').set(queue: 'other_q').perform_async('example-arg')
      assert_equal 1, Faktory::Queues['other_q'].size

      job = Faktory::Queues['other_q'].last
      assert_equal 1, job['retry']
      assert_equal 2, job['reserve_for']
      assert_equal 3, job['custom']['unique_for']
    end
  end
end
