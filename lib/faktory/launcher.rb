# encoding: utf-8
# frozen_string_literal: true
require 'faktory/manager'

module Faktory
  # The Launcher is a very simple Actor whose job is to
  # start, monitor and stop the core Actors in Faktory.
  # If any of these actors die, the Faktory executor exits
  # immediately.
  class Launcher
    include Util

    attr_accessor :manager

    def initialize(options)
      @manager = Faktory::Manager.new(options)
      @done = false
      @options = options
    end

    def run
      @thread = safe_thread("heartbeat", &method(:start_heartbeat))
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

    private unless $TESTING

    def heartbeat
      results = Faktory::CLI::PROCTITLES.map {|x| x.(self, to_data) }
      results.compact!
      $0 = results.join(' ')
    end

    def start_heartbeat
      while true
        heartbeat
        sleep 5
      end
      Faktory.logger.info("Heartbeat stopping...")
    end

    def to_data
      @data ||= begin
        {
          'hostname' => hostname,
          'started_at' => Time.now.to_f,
          'pid' => $$,
          'tag' => @options[:tag] || '',
          'concurrency' => @options[:concurrency],
          'queues' => @options[:queues].uniq,
          'labels' => @options[:labels],
          'identity' => identity,
        }
      end
    end

    def to_json
      @json ||= begin
        # this data changes infrequently so dump it to a string
        # now so we don't need to dump it every heartbeat.
        Faktory.dump_json(to_data)
      end
    end

  end
end
