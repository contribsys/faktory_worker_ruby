# encoding: utf-8
# frozen_string_literal: true
require 'faktory/manager'

module Faktory
  class Launcher
    include Util

    attr_accessor :manager

    def initialize(options)
      merged_options = Faktory.options.merge(options)
      @manager = Faktory::Manager.new(merged_options)
      @current_state = nil
      @options = merged_options
    end

    def run
      @thread = safe_thread("heartbeat", &method(:heartbeat))
      @manager.start
    end

    # Stops this instance from processing any more jobs,
    def quiet
      @current_state = 'quiet'
      @manager.quiet
    end

    # Shuts down the process.  This method does not
    # return until all work is complete and cleaned up.
    # It can take up to the timeout to complete.
    def stop
      deadline = Time.now + @options[:timeout]

      @current_state = 'terminate'
      @manager.quiet
      @manager.stop(deadline)
    end

    def stopping?
      @current_state == 'terminate'
    end

    def quiet?
      @current_state == 'quiet'
    end

    PROCTITLES = []

    private unless $TESTING

    def heartbeat
      title = ['faktory-worker', Faktory::VERSION, @options[:tag]].compact.join(" ")
      PROCTITLES << proc { title }
      PROCTITLES << proc { "[#{Processor.busy_count} of #{@options[:concurrency]} busy]" }
      PROCTITLES << proc { "stopping" if stopping? }
      PROCTITLES << proc { "quiet" if quiet? }

      loop do
        $0 = PROCTITLES.map {|p| p.call }.join(" ")

        begin
          result = Faktory.server {|c| c.beat(@current_state) }
          case result
          when "OK"
            # all good
          when "terminate"
            ::Process.kill('TERM', $$)
          when "quiet"
            ::Process.kill('TSTP', $$)
          else
            Faktory.logger.warn "Got unexpected BEAT: #{result}"
          end
        rescue => ex
          # best effort, try again in a few secs
        end
        sleep 10
      end
    end

  end
end
