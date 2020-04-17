require 'helper'
require 'active_job/queue_adapters/faktory_adapter'
require 'faktory/middleware/i18n'

# quiet a lot of AJ noise
ActiveJob::Base.logger = Logger.new(nil)

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

    it 'can pass along options' do
      # faktory_options is not thread-safe; this is not a recommended pattern to use
      # in production, set options in the ActiveJob class definition only
      TestJob.faktory_options({})
      TestJob.perform_later(123)

      TestJob.faktory_options(retry: 9)
      TestJob.perform_later(123)

      TestJob.faktory_options(retry: 9, unique_for: 10)
      TestJob.perform_later(123)

      job = ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.last
      assert_equal 9, job["retry"]
      assert_equal 10, job["custom"]["unique_for"]
      assert_equal "FaktoryAdapterTest::TestJob", job["custom"]["wrapped"]
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

    it 'executes client middlewares on push' do
      TestJob.perform_later(123)

      job = ActiveJob::QueueAdapters::FaktoryAdapter::JobWrapper.jobs.last
      assert_equal "en", job["custom"]["locale"]
    end
  end
end
