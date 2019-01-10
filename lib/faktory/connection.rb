# frozen_string_literal: true
require 'connection_pool'

module Faktory
  class Connection
    class << self
      def create(options={})
        size = Faktory.worker? ? (Faktory.options[:concurrency] + 2) : 5
        ConnectionPool.new(:timeout => options[:pool_timeout] || 1, :size => size) do
          Faktory::Client.new(options[:url] ? { url: options[:url] } : {})
        end
      end
    end
  end
end
