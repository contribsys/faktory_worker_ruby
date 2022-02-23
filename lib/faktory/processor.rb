# frozen_string_literal: true

require "faktory/util"
require "faktory/fetch"
require "faktory/job_logger"
module Faktory
  ##
  # The Processor is a standalone thread which:
  #
  # 1. fetches a job
  # 2. executes the job
  #   a. instantiate the Worker
  #   b. run the middleware chain
  #   c. call #perform
  #
  # A Processor can exit due to shutdown (processor_stopped)
  # or due to an error during job execution (processor_died)
  #
  # If an error occurs in the job execution, the
  # Processor calls the Manager to create a new one
  # to replace itself and exits.
  #
  class Processor
    include Util

    attr_reader :thread
    attr_reader :job

    @@busy_lock = Mutex.new
    @@busy_count = 0
    def self.busy_count
      @@busy_count
    end

    def initialize(mgr)
      @mgr = mgr
      @down = false
      @done = false
      @thread = nil
      @reloader = mgr.options[:reloader]
      @logging = (mgr.options[:job_logger] || Faktory::JobLogger).new
      @fetcher = Faktory::Fetcher.new(mgr.options)
    end

    def terminate(wait = false)
      @done = true
      return if !@thread
      @thread.value if wait
    end

    def kill(wait = false)
      @done = true
      return if !@thread
      # unlike the other actors, terminate does not wait
      # for the thread to finish because we don't know how
      # long the job will take to finish.  Instead we
      # provide a `kill` method to call after the shutdown
      # timeout passes.
      @thread.raise ::Faktory::Shutdown
      @thread.value if wait
    end

    def start
      @thread ||= safe_thread("processor", &method(:run))
    end

    private unless $TESTING

    def run
      until @done
        process_one
      end
      @mgr.processor_stopped(self)
    rescue Faktory::Shutdown
      @mgr.processor_stopped(self)
    rescue Exception => ex
      @mgr.processor_died(self, ex)
    end

    def process_one
      work = fetch
      if work
        @@busy_lock.synchronize do
          @@busy_count += 1
        end
        begin
          @job = work.job
          process(work)
        ensure
          @@busy_lock.synchronize do
            @@busy_count -= 1
          end
        end
      else
        sleep 1
      end
    end

    def fetch
      work = @fetcher.retrieve_work
      if @down
        (logger.info { "Faktory is online, #{Time.now - @down} sec downtime" }
         @down = nil)
      end
      work
    rescue Faktory::Shutdown
    rescue => ex
      handle_fetch_exception(ex)
    end

    def handle_fetch_exception(ex)
      if !@down
        @down = Time.now
        logger.error("Error fetching job: #{ex}")
        ex.backtrace.each do |bt|
          logger.error(bt)
        end
      end
      sleep(1)
      nil
    end

    def dispatch(payload)
      Faktory::Logging.with_job_hash_context(payload) do
        @logging.call(payload) do
          # Rails 5 requires a Reloader to wrap code execution.  In order to
          # constantize the worker and instantiate an instance, we have to call
          # the Reloader.  It handles code loading, db connection management, etc.
          # Effectively this block denotes a "unit of work" to Rails.
          @reloader.call do
            klass = constantize(payload["jobtype"])
            jobinst = klass.new
            jobinst.jid = payload["jid"]
            yield jobinst
          end
        end
      end
    end

    def process(work)
      payload = work.job
      begin
        dispatch(payload) do |jobinst|
          Faktory.worker_middleware.invoke(jobinst, payload) do
            jobinst.perform(*payload["args"])
          end
        end
        work.acknowledge
      rescue Faktory::Shutdown => shut
        # Had to force kill this job because it didn't finish within
        # the timeout.  Fail it so we can release any locks server-side
        # and immediately restart it.
        work.fail(shut)
      rescue Exception => ex
        handle_exception(ex, {context: "Job raised exception", job: work.job})
        work.fail(ex)
        raise ex
      end
    end

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    def constantize(str)
      names = str.split("::")
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
    end
  end
end
