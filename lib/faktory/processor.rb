# frozen_string_literal: true
require 'faktory/util'
require 'faktory/fetch'
require 'faktory/job_logger'
require 'faktory/job_retry'
require 'thread'

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

    def initialize(mgr)
      @mgr = mgr
      @down = false
      @done = false
      @job = nil
      @thread = nil
      @reloader = Faktory.options[:reloader]
      @logging = (mgr.options[:job_logger] || Faktory::JobLogger).new
      @retrier = Faktory::JobRetry.new
      @fetcher = Faktory::Fetcher.new(Faktory.options)
    end

    def terminate(wait=false)
      @done = true
      return if !@thread
      @thread.value if wait
    end

    def kill(wait=false)
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
      begin
        while !@done
          process_one
        end
        @mgr.processor_stopped(self)
      rescue Faktory::Shutdown
        @mgr.processor_stopped(self)
      rescue Exception => ex
        @mgr.processor_died(self, ex)
      end
    end

    def process_one
      @job = fetch
      process(@job) if @job
      @job = nil
    end

    def fetch
      begin
        work = @fetcher.retrieve_work
        (logger.info { "Faktory is online, #{Time.now - @down} sec downtime" }; @down = nil) if @down
        work
      rescue Faktory::Shutdown
      rescue => ex
        handle_fetch_exception(ex)
      end
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

    def dispatch(job_hash)
      # since middleware can mutate the job hash
      # we clone here so we report the original
      # job structure to the Web UI
      pristine = cloned(job_hash)

      Faktory::Logging.with_job_hash_context(job_hash) do
        @logging.call(job_hash) do
          # Rails 5 requires a Reloader to wrap code execution.  In order to
          # constantize the worker and instantiate an instance, we have to call
          # the Reloader.  It handles code loading, db connection management, etc.
          # Effectively this block denotes a "unit of work" to Rails.
          @reloader.call do
            klass  = constantize(job_hash['jobtype'.freeze])
            worker = klass.new
            worker.jid = job_hash['jid'.freeze]
            yield worker
          end
        end
      end
    end

    def process(work)
      jobstr = work.job
      queue = work.queue_name

      begin
        job_hash = JSON.parse(jobstr)
        dispatch(job_hash) do |worker|
          Faktory.exec_middleware.invoke(worker, job_hash) do
            execute_job(worker, job_hash['args'.freeze])
          end
        end
        work.acknowledge
      rescue Faktory::Shutdown
        # Had to force kill this job because it didn't finish
        # within the timeout.  Don't acknowledge the work since
        # we didn't properly finish it.
      rescue Exception => ex
        handle_exception(ex, { :context => "Job raised exception", :job => job_hash, :jobstr => jobstr })
        work.fail(ex)
        raise ex
      end
    end

    def execute_job(worker, cloned_args)
      worker.perform(*cloned_args)
    end

    def thread_identity
      @str ||= Thread.current.object_id.to_s(36)
    end

    def constantize(str)
      names = str.split('::')
      names.shift if names.empty? || names.first.empty?

      names.inject(Object) do |constant, name|
        constant.const_defined?(name) ? constant.const_get(name) : constant.const_missing(name)
      end
    end

  end
end
