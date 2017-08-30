# frozen_string_literal: true
require 'connection_pool'
require 'uri'

module Faktory
  class Connection
    class << self

      def create(options={})
        options.keys.each do |key|
          options[key.to_sym] = options.delete(key)
        end

        options[:url] ||= determine_provider

        size = options[:size] || (Faktory.worker? ? (Faktory.options[:concurrency] + 5) : 5)

        verify_sizing(size, Faktory.options[:concurrency]) if Faktory.worker?

        pool_timeout = options[:pool_timeout] || 1
        log_info(options)

        ConnectionPool.new(:timeout => pool_timeout, :size => size) do
          Faktory::Client.new(options)
        end
      end

      private

      # Faktory needs a lot of concurrent connections.
      def verify_sizing(size, concurrency)
        raise ArgumentError, "Your connection pool is too small for Faktory to work. Your pool has #{size} connections but really needs to have at least #{concurrency + 2}" if size <= concurrency
      end

      def log_info(options)
        # Don't log AHOY password
        redacted = "REDACTED"
        scrubbed_options = options.dup
        if scrubbed_options[:url] && (uri = URI.parse(scrubbed_options[:url])) && uri.password
          uri.password = redacted
          scrubbed_options[:url] = uri.to_s
        end
        if scrubbed_options[:password]
          scrubbed_options[:password] = redacted
        end
        if Faktory.exec?
          Faktory.logger.info("Booting Faktory executor #{Faktory::VERSION} with options #{scrubbed_options}")
        else
          Faktory.logger.debug("#{Faktory::NAME} client with options #{scrubbed_options}")
        end
      end

      def determine_provider
        raise "Invalid FAKTORY_PROVIDER value, should not be a URL" if ENV['FAKTORY_PROVIDER'] =~ /:/

        # If you have this in your environment:
        # MY_FAKTORY_URL=tcp://hostname.example.com:1238/4
        # then set:
        # FAKTORY_PROVIDER=MY_FAKTORY_URL
        # and Faktory will find your custom URL variable with no custom
        # initialization code at all.
        ENV[
          ENV['FAKTORY_PROVIDER'] || 'FAKTORY_URL'
        ]
      end

    end
  end
end
