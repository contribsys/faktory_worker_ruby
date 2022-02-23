# frozen_string_literal: true

require "socket"
require "securerandom"
require "faktory/exception_handler"

module Faktory
  ##
  # This module is part of Faktory core and not intended for extensions.
  #
  module Util
    include ExceptionHandler

    EXPIRY = 60 * 60 * 24

    def watchdog(last_words)
      yield
    rescue Exception => ex
      handle_exception(ex, {context: last_words})
      raise ex
    end

    def safe_thread(name, &block)
      Thread.new do
        Thread.current["faktory_label"] = name
        watchdog(name, &block)
      end
    end

    def logger
      Faktory.logger
    end

    def server(&block)
      Faktory.server(&block)
    end

    def hostname
      ENV["DYNO"] || Socket.gethostname
    end

    def process_nonce
      @@process_nonce ||= SecureRandom.hex(6)
    end

    def identity
      @@identity ||= "#{hostname}:#{$$}:#{process_nonce}"
    end

    def fire_event(event, reverse = false)
      arr = Faktory.options[:lifecycle_events][event]
      arr.reverse! if reverse
      arr.each do |block|
        block.call
      rescue => ex
        handle_exception(ex, {context: "Exception during Faktory lifecycle event.", event: event})
      end
      arr.clear
    end
  end
end
