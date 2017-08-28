# encoding: utf-8
# frozen_string_literal: true
require 'faktory/util'
require 'faktory/processor'
require 'faktory/fetch'
require 'thread'
require 'set'

module Faktory

  ##
  # The Manager is the central coordination point in Faktory, controlling
  # the lifecycle of the Processors.
  #
  # Tasks:
  #
  # 1. start: Spin up Processors.
  # 3. processor_died: Handle job failure, throw away Processor, create new one.
  # 4. quiet: shutdown idle Processors.
  # 5. stop: hard stop the Processors by deadline.
  #
  # Note that only the last task requires its own Thread since it has to monitor
  # the shutdown process.  The other tasks are performed by other threads.
  #
  class Manager
    include Util

    attr_reader :threads
    attr_reader :options

    def initialize(options={})
      logger.debug { options.inspect }
      @options = options
      @count = options[:concurrency] || 25
      raise ArgumentError, "Concurrency of #{@count} is not supported" if @count < 1

      @done = false
      @threads = Set.new
      @count.times do
        @threads << Processor.new(self)
      end
      @plock = Mutex.new
    end

    def start
      @threads.each do |x|
        x.start
      end
    end

    def quiet
      return if @done
      @done = true

      logger.info { "Terminating quiet threads" }
      @threads.each { |x| x.terminate }
      fire_event(:quiet, true)
    end

    # hack for quicker development / testing environment #2774
    PAUSE_TIME = STDOUT.tty? ? 0.1 : 0.5

    def stop(deadline)
      quiet
      fire_event(:shutdown, true)

      # some of the shutdown events can be async,
      # we don't have any way to know when they're done but
      # give them a little time to take effect
      sleep PAUSE_TIME
      return if @threads.empty?

      logger.info { "Pausing to allow threads to finish..." }
      remaining = deadline - Time.now
      while remaining > PAUSE_TIME
        return if @threads.empty?
        sleep PAUSE_TIME
        remaining = deadline - Time.now
      end
      return if @threads.empty?

      hard_shutdown
    end

    def processor_stopped(processor)
      @plock.synchronize do
        @threads.delete(processor)
      end
    end

    def processor_died(processor, reason)
      @plock.synchronize do
        @threads.delete(processor)
        unless @done
          p = Processor.new(self)
          @threads << p
          p.start
        end
      end
    end

    def stopped?
      @done
    end

    private

    def hard_shutdown
      # We've reached the timeout and we still have busy threads.
      # They must die but their jobs shall live on.
      cleanup = nil
      @plock.synchronize do
        cleanup = @threads.dup
      end

      if cleanup.size > 0
        jobs = cleanup.map {|p| p.job }.compact

        logger.warn { "Terminating #{cleanup.size} busy worker threads" }
        logger.warn { "Work still in progress #{jobs.inspect}" }
      end

      cleanup.each do |processor|
        processor.kill
      end
    end

  end
end
