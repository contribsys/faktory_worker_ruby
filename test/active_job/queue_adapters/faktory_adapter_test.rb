require 'helper'
require 'active_job/queue_adapters/faktory_adapter'

class FaktoryAdapterTest < LiveTest
  describe 'ActiveJob adapter' do

    class TestJob < ActiveJob::Base
      self.queue_adapter = :faktory
      cattr_accessor :count
      @count = 0
      def perform(*args)
        args.each do |value|
          self.class.count += value
        end
      end
    end

    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
      ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.clear
      TestJob.count = 0
    end

    after do
      Faktory::Queues.clear_all
      Faktory::Testing.disable!
    end

    it 'queues a job in the JobWrapper queue' do
      assert_equal 0, ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.size
      TestJob.perform_later(42)
      assert_equal 1, ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.size
    end

    it 'can pass along a priority' do
      TestJob.set(priority: 9).perform_later(123)
      job = ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.last
      assert_equal 9, job["priority"]
    end

    it 'can perform a job' do
      TestJob.perform_later(42)
      ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.drain
      assert_equal 42, TestJob.count
    end

    it 'can perform a job with multiple arguments' do
      TestJob.perform_later(1,2,3)
      ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.drain
      assert_equal 6, TestJob.count
    end

  end
end
