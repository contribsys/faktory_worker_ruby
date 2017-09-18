# encoding: utf-8
# frozen_string_literal: true
require 'faktory/manager'

module Faktory
  class Launcher
    include Util

    attr_accessor :manager

    def initialize(options)
      @manager = Faktory::Manager.new(options)
      @done = false
      @options = options
    end

    def run
      @thread = safe_thread("heartbeat", &method(:heartbeat))
      @manager.start
    end

    # Stops this instance from processing any more jobs,
    def quiet
      @done = true
      @manager.quiet
    end

    # Shuts down the process.  This method does not
    # return until all work is complete and cleaned up.
    # It can take up to the timeout to complete.
    def stop
      deadline = Time.now + @options[:timeout]

      @done = true
      @manager.quiet
      @manager.stop(deadline)
    end

    def stopping?
      @done
    end

    PROCTITLES = []

    private unless $TESTING

    def heartbeat
      title = ['faktory-worker', Faktory::VERSION, @options[:tag]].compact.join(" ")
      PROCTITLES << proc { title }
      PROCTITLES << proc { "[#{Processor.busy_count} of #{@options[:concurrency]} busy]" }
      PROCTITLES << proc { "stopping" if stopping? }

      loop do
        $0 = PROCTITLES.map {|p| p.call }.join(" ")

        begin
          Faktory.server {|c| c.beat }
        rescue => ex
          # best effort, try again in a few secs
        end
        sleep 10
      end
    end

  end
end
