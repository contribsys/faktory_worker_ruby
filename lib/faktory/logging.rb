# frozen_string_literal: true
require 'time'
require 'logger'
require 'fcntl'

module Faktory
  module Logging

    class Pretty < Logger::Formatter
      SPACE = " "

      # Provide a call() method that returns the formatted message.
      def call(severity, time, program_name, message)
        "#{time.utc.iso8601(3)} #{::Process.pid} TID-#{Thread.current.object_id.to_s(36)}#{context} #{severity}: #{message}\n"
      end

      def context
        c = Thread.current[:faktory_context]
        " #{c.join(SPACE)}" if c && c.any?
      end
    end

    class WithoutTimestamp < Pretty
      def call(severity, time, program_name, message)
        "#{::Process.pid} TID-#{Thread.current.object_id.to_s(36)}#{context} #{severity}: #{message}\n"
      end
    end

    def self.job_hash_context(job_hash)
      # If we're using a wrapper class, like ActiveJob, use the "wrapped"
      # attribute to expose the underlying thing.
      klass = job_hash['wrapped'.freeze] || job_hash["class".freeze]
      "#{klass} JID-#{job_hash['jid'.freeze]}"
    end

    def self.with_job_hash_context(job_hash, &block)
      with_context(job_hash_context(job_hash), &block)
    end

    def self.with_context(msg)
      Thread.current[:faktory_context] ||= []
      Thread.current[:faktory_context] << msg
      yield
    ensure
      Thread.current[:faktory_context].pop
    end

    def self.initialize_logger(log_target = STDOUT)
      oldlogger = defined?(@logger) ? @logger : nil
      @logger = Logger.new(log_target)
      @logger.level = Logger::INFO
      # We assume that any TTY is logging directly to a terminal and needs timestamps.
      # We assume that any non-TTY is logging to Upstart/Systemd/syslog/Heroku/etc with a decent
      # logging subsystem that provides a timestamp for each entry.
      @logger.formatter = log_target.tty? ? Pretty.new : WithoutTimestamp.new
      oldlogger.close if oldlogger && !$TESTING # don't want to close testing's STDOUT logging
      @logger
    end

    def self.logger
      defined?(@logger) ? @logger : initialize_logger
    end

    def self.logger=(log)
      @logger = (log ? log : Logger.new(File::NULL))
    end

    def logger
      Faktory::Logging.logger
    end
  end
end
