# frozen_string_literal: true

require "connection_pool"

module Faktory
  class Connection
    class << self
      def create(options = {})
        size = Faktory.worker? ? (Faktory.options[:concurrency] + 5) : 20
        ConnectionPool.new(timeout: options[:pool_timeout] || 1, size: size) do
          Faktory::Client.new(**options)
        end
      end
    end
  end
end
