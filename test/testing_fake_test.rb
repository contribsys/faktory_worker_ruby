require 'helper'

class TestingFakeTest < LiveTest
  describe 'faktory testing' do
    class PerformError < RuntimeError; end

    class DirectJob
      include Faktory::Job
      def perform(a, b)
        a + b
      end
    end

    class EnqueuedJob
      include Faktory::Job
      def perform(a, b)
        a + b
      end
    end

    class StoredJob
      include Faktory::Job
      def perform(error)
        raise PerformError if error
      end
    end

    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
      EnqueuedJob.jobs.clear
      DirectJob.jobs.clear
    end

    after do
      Faktory::Queues.clear_all
      Faktory::Testing.disable!
    end

    it 'stubs the async call' do
      assert_equal 0, DirectJob.jobs.size
      assert DirectJob.perform_async(1, 2)
      assert_in_delta Time.now.to_f, DirectJob.jobs.last['enqueued_at'], 0.1
      assert_equal 1, DirectJob.jobs.size
      assert DirectJob.perform_in(10, 1, 2)
      refute DirectJob.jobs.last['enqueued_at']
      assert_equal 2, DirectJob.jobs.size
      assert DirectJob.perform_at(10, 1, 2)
      assert_equal 3, DirectJob.jobs.size
      assert_in_delta Time.now.to_f, Time.parse(DirectJob.jobs.last['at']).to_f, 10.1
    end

    it 'stubs the push call' do
      assert_equal 0, EnqueuedJob.jobs.size
      assert Faktory::Client.new.push({
        "jid" => SecureRandom.hex(12),
        "queue" => "default",
        "jobtype" => EnqueuedJob,
        "args" => [1,2]
      })
      assert_equal 1, EnqueuedJob.jobs.size
    end

    it 'executes all stored jobs' do
      assert StoredJob.perform_async(false)
      assert StoredJob.perform_async(true)

      assert_equal 2, StoredJob.jobs.size
      assert_raises PerformError do
        StoredJob.drain
      end
      assert_equal 0, StoredJob.jobs.size
    end

    class SpecificJidJob
      include Faktory::Job
      faktory_class_attribute :count
      self.count = 0
      def perform(worker_jid)
        return unless worker_jid == self.jid
        self.class.count += 1
      end
    end

    it 'execute only jobs with assigned JID' do
      4.times do |i|
        jid = SpecificJidJob.perform_async(nil)
        if i % 2 == 0
          SpecificJidJob.jobs[-1]["args"] = ["wrong_jid"]
        else
          SpecificJidJob.jobs[-1]["args"] = [jid]
        end
      end

      SpecificJidJob.perform_one
      assert_equal 0, SpecificJidJob.count

      SpecificJidJob.perform_one
      assert_equal 1, SpecificJidJob.count

      SpecificJidJob.drain
      assert_equal 2, SpecificJidJob.count
    end

    it 'round trip serializes the job arguments' do
      assert StoredJob.perform_async(:mike)
      job = StoredJob.jobs.first
      assert_equal "mike", job['args'].first
      StoredJob.clear
    end

    it 'perform_one runs only one job' do
      DirectJob.perform_async(1, 2)
      DirectJob.perform_async(3, 4)
      assert_equal 2, DirectJob.jobs.size

      DirectJob.perform_one
      assert_equal 1, DirectJob.jobs.size

      DirectJob.clear
    end

    it 'perform_one raise error upon empty queue' do
      DirectJob.clear
      assert_raises Faktory::EmptyQueueError do
        DirectJob.perform_one
      end
    end

    class FirstJob
      include Faktory::Job
      faktory_class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class SecondJob
      include Faktory::Job
      faktory_class_attribute :count
      self.count = 0
      def perform
        self.class.count += 1
      end
    end

    class ThirdJob
      include Faktory::Job
      faktory_class_attribute :count
      def perform
        FirstJob.perform_async
        SecondJob.perform_async
      end
    end

    it 'clears jobs across all workers' do
      Faktory::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      FirstJob.perform_async
      SecondJob.perform_async

      assert_equal 1, FirstJob.jobs.size
      assert_equal 1, SecondJob.jobs.size

      Faktory::Job.clear_all

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count
    end

    it 'drains jobs across all workers' do
      Faktory::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count

      FirstJob.perform_async
      SecondJob.perform_async

      assert_equal 1, FirstJob.jobs.size
      assert_equal 1, SecondJob.jobs.size

      Faktory::Job.drain_all

      assert_equal 0, FirstJob.jobs.size
      assert_equal 0, SecondJob.jobs.size

      assert_equal 1, FirstJob.count
      assert_equal 1, SecondJob.count
    end

    it 'drains jobs across all workers even when workers create new jobs' do
      Faktory::Job.jobs.clear
      FirstJob.count = 0
      SecondJob.count = 0

      assert_equal 0, ThirdJob.jobs.size

      assert_equal 0, FirstJob.count
      assert_equal 0, SecondJob.count

      ThirdJob.perform_async

      assert_equal 1, ThirdJob.jobs.size

      Faktory::Job.drain_all

      assert_equal 0, ThirdJob.jobs.size

      assert_equal 1, FirstJob.count
      assert_equal 1, SecondJob.count
    end

    class AltQueueJob
      include Faktory::Job
      faktory_options queue: :alt
      def perform(a, b)
        a + b
      end
    end

    it 'drains jobs of workers with symbolized queue names' do
      Faktory::Job.jobs.clear

      AltQueueJob.perform_async(5,6)
      assert_equal 1, AltQueueJob.jobs.size

      Faktory::Job.drain_all
      assert_equal 0, AltQueueJob.jobs.size
    end

    it 'can execute a job' do
      DirectJob.execute_job(DirectJob.new, [2, 3])
    end
  end

  describe 'queue testing' do
    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
    end

    after do
      Faktory::Testing.disable!
      Faktory::Queues.clear_all
    end

    class QueueJob
      include Faktory::Job
      def perform(a, b)
        a + b
      end
    end

    it 'finds enqueued jobs' do
      assert_equal 0, Faktory::Queues["default"].size

      QueueJob.perform_async(1, 2)
      QueueJob.perform_async(1, 2)
      AltQueueJob.perform_async(1, 2)

      assert_equal 2, Faktory::Queues["default"].size
      assert_equal [1, 2], Faktory::Queues["default"].first["args"]

      assert_equal 1, Faktory::Queues["alt"].size
    end

    it 'clears out all queues' do
      assert_equal 0, Faktory::Queues["default"].size

      QueueJob.perform_async(1, 2)
      QueueJob.perform_async(1, 2)
      AltQueueJob.perform_async(1, 2)

      Faktory::Queues.clear_all

      assert_equal 0, Faktory::Queues["default"].size
      assert_equal 0, QueueJob.jobs.size
      assert_equal 0, Faktory::Queues["alt"].size
      assert_equal 0, AltQueueJob.jobs.size
    end

    it 'finds jobs enqueued by client' do
      Faktory::Client.new.push({
        'jid' => SecureRandom.hex(12),
        'jobtype' => 'NonExistentJob',
        'queue' => 'missing',
        'args' => [1]
      })

      assert_equal 1, Faktory::Queues["missing"].size
    end

    it 'respects underlying array changes' do
      # Rspec expect change() syntax saves a reference to
      # an underlying array. When the array containing jobs is
      # derived, Rspec test using `change(QueueJob.jobs, :size).by(1)`
      # won't pass. This attempts to recreate that scenario
      # by saving a reference to the jobs array and ensuring
      # it changes properly on enqueueing
      jobs = QueueJob.jobs
      assert_equal 0, jobs.size
      QueueJob.perform_async(1, 2)
      assert_equal 1, jobs.size
    end
  end

  describe 'polyglot testing' do
    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
    end

    after do
      Faktory::Testing.disable!
      Faktory::Queues.clear_all
    end

    it 'perform_async' do
      Faktory::Job.perform_async('someFunc', ['some', 'args'], queue: 'some_q')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].first
      assert_equal 'someFunc', job['jobtype']
      assert_equal 'some_q', job['queue']
      assert_equal ['some', 'args'], job['args']
    end

    it 'perform_in' do
      Faktory::Job.perform_in(10, 'someFunc', ['some', 'args'], queue: 'some_q')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].first
      assert_equal 'someFunc', job['jobtype']
      assert_equal 'some_q', job['queue']
      assert_equal ['some', 'args'], job['args']
      assert_in_delta Time.now.to_f, Time.parse(job['at']).to_f, 10.1
    end
  end
end
