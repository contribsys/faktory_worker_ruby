module Faktory
  module Testing
    def self.__test_mode
      @__test_mode
    end

    def self.__test_mode=(mode)
      @__test_mode = mode
    end

    def self.__set_test_mode(mode)
      if block_given?
        current_mode = __test_mode
        begin
          self.__test_mode = mode
          yield
        ensure
          self.__test_mode = current_mode
        end
      else
        self.__test_mode = mode
      end
    end

    def self.disable!(&block)
      __set_test_mode(:disable, &block)
    end

    def self.fake!(&block)
      __set_test_mode(:fake, &block)
    end

    def self.inline!(&block)
      # Only allow inline testing inside of a block
      # https://github.com/mperham/sidekiq/issues/3495
      unless block
        raise "Must provide a block to Faktory::Testing.inline!"
      end

      __set_test_mode(:inline, &block)
    end

    def self.enabled?
      __test_mode != :disable
    end

    def self.disabled?
      __test_mode == :disable
    end

    def self.fake?
      __test_mode == :fake
    end

    def self.inline?
      __test_mode == :inline
    end

    def self.constantize(str)
      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        # the false flag limits search for name to under the constant namespace
        # which mimics Rails' behaviour
        constant.const_defined?(name, false) ? constant.const_get(name, false) : constant.const_missing(name)
      end
    end
  end

  # Test modes have to be opted into explicitly.
  # Just requiring the testing module shouldn't automatically change the testing mode.
  Faktory::Testing.disable!

  class EmptyQueueError < RuntimeError; end

  class Client
    alias_method :real_push, :push
    alias_method :real_open_socket, :open_socket

    def push(job)
      if Faktory::Testing.inline?
        job = Faktory.load_json(Faktory.dump_json(job))
        job_class = Faktory::Testing.constantize(job["jobtype"])
        job_class.new.perform(*job["args"])
        job["jid"]
      elsif Faktory::Testing.fake?
        job = Faktory.load_json(Faktory.dump_json(job))
        job["enqueued_at"] = Time.now.to_f unless job["at"]
        Queues.push(job["queue"], job["jobtype"], job)
        job["jid"]
      else
        real_push(job)
      end
    end

    def open_socket(*args)
      unless Faktory::Testing.enabled?
        real_open_socket(*args)
      end
    end
  end

  module Queues
    ##
    # The Queues class is only for testing the fake queue implementation.
    # There are 2 data structures involved in tandem. This is due to the
    # Rspec syntax of change(QueueWorker.jobs, :size). It keeps a reference
    # to the array. Because the array was dervied from a filter of the total
    # jobs enqueued, it appeared as though the array didn't change.
    #
    # To solve this, we'll keep 2 hashes containing the jobs. One with keys based
    # on the queue, and another with keys of the worker names, so the array for
    # QueueWorker.jobs is a straight reference to a real array.
    #
    # Queue-based hash:
    #
    # {
    #   "default"=>[
    #     {
    #       "class"=>"TestTesting::QueueWorker",
    #       "args"=>[1, 2],
    #       "retry"=>true,
    #       "queue"=>"default",
    #       "jid"=>"abc5b065c5c4b27fc1102833",
    #       "created_at"=>1447445554.419934
    #     }
    #   ]
    # }
    #
    # Worker-based hash:
    #
    # {
    #   "TestTesting::QueueWorker"=>[
    #     {
    #       "class"=>"TestTesting::QueueWorker",
    #       "args"=>[1, 2],
    #       "retry"=>true,
    #       "queue"=>"default",
    #       "jid"=>"abc5b065c5c4b27fc1102833",
    #       "created_at"=>1447445554.419934
    #     }
    #   ]
    # }
    #
    # Example:
    #
    #   require 'faktory/testing'
    #
    #   assert_equal 0, Faktory::Queues["default"].size
    #   HardWorker.perform_async(:something)
    #   assert_equal 1, Faktory::Queues["default"].size
    #   assert_equal :something, Faktory::Queues["default"].first['args'][0]
    #
    # You can also clear all workers' jobs:
    #
    #   assert_equal 0, Faktory::Queues["default"].size
    #   HardWorker.perform_async(:something)
    #   Faktory::Queues.clear_all
    #   assert_equal 0, Faktory::Queues["default"].size
    #
    # This can be useful to make sure jobs don't linger between tests:
    #
    #   RSpec.configure do |config|
    #     config.before(:each) do
    #       Faktory::Queues.clear_all
    #     end
    #   end
    #
    class << self
      def [](queue)
        jobs_by_queue[queue]
      end

      def push(queue, klass, job)
        jobs_by_queue[queue] << job
        jobs_by_worker[klass] << job
      end

      def jobs_by_queue
        @jobs_by_queue ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def jobs_by_worker
        @jobs_by_worker ||= Hash.new { |hash, key| hash[key] = [] }
      end

      def delete_for(jid, queue, klass)
        jobs_by_queue[queue.to_s].delete_if { |job| job["jid"] == jid }
        jobs_by_worker[klass].delete_if { |job| job["jid"] == jid }
      end

      def clear_for(queue, klass)
        jobs_by_queue[queue].clear
        jobs_by_worker[klass].clear
      end

      def clear_all
        jobs_by_queue.clear
        jobs_by_worker.clear
      end
    end
  end

  module Job
    ##
    # The Faktory testing infrastructure overrides perform_async
    # so that it does not actually touch the network.  Instead it
    # stores the asynchronous jobs in a per-class array so that
    # their presence/absence can be asserted by your tests.
    #
    # This is similar to ActionMailer's :test delivery_method and its
    # ActionMailer::Base.deliveries array.
    #
    # Example:
    #
    #   require 'faktory/testing'
    #
    #   assert_equal 0, HardWorker.jobs.size
    #   HardWorker.perform_async(:something)
    #   assert_equal 1, HardWorker.jobs.size
    #   assert_equal :something, HardWorker.jobs[0]['args'][0]
    #
    #   assert_equal 0, Faktory::Extensions::DelayedMailer.jobs.size
    #   MyMailer.delay.send_welcome_email('foo@example.com')
    #   assert_equal 1, Faktory::Extensions::DelayedMailer.jobs.size
    #
    # You can also clear and drain all workers' jobs:
    #
    #   assert_equal 0, Faktory::Extensions::DelayedMailer.jobs.size
    #   assert_equal 0, Faktory::Extensions::DelayedModel.jobs.size
    #
    #   MyMailer.delay.send_welcome_email('foo@example.com')
    #   MyModel.delay.do_something_hard
    #
    #   assert_equal 1, Faktory::Extensions::DelayedMailer.jobs.size
    #   assert_equal 1, Faktory::Extensions::DelayedModel.jobs.size
    #
    #   Faktory::Worker.clear_all # or .drain_all
    #
    #   assert_equal 0, Faktory::Extensions::DelayedMailer.jobs.size
    #   assert_equal 0, Faktory::Extensions::DelayedModel.jobs.size
    #
    # This can be useful to make sure jobs don't linger between tests:
    #
    #   RSpec.configure do |config|
    #     config.before(:each) do
    #       Faktory::Worker.clear_all
    #     end
    #   end
    #
    # or for acceptance testing, i.e. with cucumber:
    #
    #   AfterStep do
    #     Faktory::Worker.drain_all
    #   end
    #
    #   When I sign up as "foo@example.com"
    #   Then I should receive a welcome email to "foo@example.com"
    #
    module ClassMethods
      # Queue for this worker
      def queue
        faktory_options["queue"]
      end

      # Jobs queued for this worker
      def jobs
        Queues.jobs_by_worker[to_s]
      end

      # Clear all jobs for this worker
      def clear
        Queues.clear_for(queue, to_s)
      end

      # Drain and run all jobs for this worker
      def drain
        while jobs.any?
          next_job = jobs.first
          Queues.delete_for(next_job["jid"], next_job["queue"], to_s)
          process_job(next_job)
        end
      end

      # Pop out a single job and perform it
      def perform_one
        raise(EmptyQueueError, "perform_one called with empty job queue") if jobs.empty?
        next_job = jobs.first
        Queues.delete_for(next_job["jid"], queue, to_s)
        process_job(next_job)
      end

      def process_job(job)
        worker = new
        worker.jid = job["jid"]
        worker.bid = job["bid"] if worker.respond_to?(:bid=)
        # Faktory::Testing.server_middleware.invoke(worker, job, job['queue']) do
        execute_job(worker, job["args"])
        # end
      end

      def execute_job(worker, args)
        worker.perform(*args)
      end
    end

    class << self
      def jobs # :nodoc:
        Queues.jobs_by_queue.values.flatten
      end

      # Clear all queued jobs across all workers
      def clear_all
        Queues.clear_all
      end

      # Drain all queued jobs across all workers
      def drain_all
        while jobs.any?
          worker_classes = jobs.map { |job| job["jobtype"] }.uniq

          worker_classes.each do |worker_class|
            Faktory::Testing.constantize(worker_class).drain
          end
        end
      end
    end
  end
end
