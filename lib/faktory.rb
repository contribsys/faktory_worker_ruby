# encoding: utf-8
# frozen_string_literal: true
require 'faktory/version'

require 'faktory/logging'
require 'faktory/client'
require 'faktory/middleware/chain'
require 'faktory/job'
require 'faktory/connection'

require 'json'

module Faktory
  NAME = 'Faktory'.freeze
  LICENSE = 'See LICENSE and the LGPL-3.0 for licensing details.'

  DEFAULTS = {
    queues: [],
    concurrency: 20,
    require: '.',
    environment: 'development',
    timeout: 28,
    error_handlers: [],
    lifecycle_events: {
      startup: [],
      quiet: [],
      shutdown: [],
    },
    reloader: proc { |&block| block.call },
  }

  DEFAULT_WORKER_OPTIONS = {
    'retry' => true,
    'queue' => 'default'
  }

  def self.options
    @options ||= DEFAULTS.dup
  end
  def self.options=(opts)
    @options = opts
  end

  ##
  # Configuration for Faktory executor, use like:
  #
  #   Faktory.configure_worker do |config|
  #     config.faktory = { :url => 'myhost:7419' }
  #     config.exec_middleware do |chain|
  #       chain.add MyServerHook
  #     end
  #   end
  def self.configure_worker
    yield self if worker?
  end

  ##
  # Configuration for Faktory client, use like:
  #
  #   Faktory.configure_client do |config|
  #     config.faktory = { :size => 1, :url => 'myhost:7419' }
  #   end
  def self.configure_client
    yield self unless worker?
  end

  def self.worker?
    defined?(Faktory::CLI)
  end

  def self.server
    raise ArgumentError, "requires a block" unless block_given?
    faktory_pool.with do |conn|
      yield conn
    end
  end

  def self.faktory_pool
    @redis ||= Faktory::Connection.create
  end

  def self.faktory=(hash)
    @redis = if hash.is_a?(ConnectionPool)
      hash
    else
      Faktory::Connection.create(hash)
    end
  end

  def self.client_middleware
    @client_chain ||= Middleware::Chain.new
    yield @client_chain if block_given?
    @client_chain
  end

  def self.worker_middleware
    @server_chain ||= Middleware::Chain.new
    yield @server_chain if block_given?
    @server_chain
  end

  def self.default_worker_options=(hash)
    # stringify
    @default_worker_options = default_worker_options.merge(Hash[hash.map{|k, v| [k.to_s, v]}])
  end
  def self.default_worker_options
    defined?(@default_worker_options) ? @default_worker_options : DEFAULT_WORKER_OPTIONS
  end

  def self.load_json(string)
    JSON.parse(string)
  end
  def self.dump_json(object)
    JSON.generate(object)
  end

  def self.logger
    Faktory::Logging.logger
  end
  def self.logger=(log)
    Faktory::Logging.logger = log
  end

  # Register a proc to handle any error which occurs within the Faktory process.
  #
  #   Faktory.configure_worker do |config|
  #     config.error_handlers << proc {|ex,ctx_hash| MyErrorService.notify(ex, ctx_hash) }
  #   end
  #
  # The default error handler logs errors to Faktory.logger.
  def self.error_handlers
    self.options[:error_handlers]
  end

  # Register a block to run at a point in the Faktory lifecycle.
  # :startup, :quiet or :shutdown are valid events.
  #
  #   Faktory.configure_worker do |config|
  #     config.on(:shutdown) do
  #       puts "Goodbye cruel world!"
  #     end
  #   end
  def self.on(event, &block)
    raise ArgumentError, "Symbols only please: #{event}" unless event.is_a?(Symbol)
    raise ArgumentError, "Invalid event name: #{event}" unless options[:lifecycle_events].key?(event)
    options[:lifecycle_events][event] << block
  end

  # We are shutting down Faktory but what about workers that
  # are working on some long job?  This error is
  # raised in workers that have not finished within the hard
  # timeout limit.  This is needed to rollback db transactions,
  # otherwise Ruby's Thread#kill will commit.
  # DO NOT RESCUE THIS ERROR IN YOUR WORKERS
  class Shutdown < Interrupt; end
end

require 'faktory/rails' if defined?(::Rails::Engine)
