# encoding: utf-8
# frozen_string_literal: true
require 'faktory/version'

require 'faktory/logging'
require 'faktory/client'
require 'faktory/middleware/chain'
require 'faktory/job'
require 'faktory/connection'

require 'json'

require 'active_job/queue_adapters/faktory_adapter' if defined?(Rails)

module Faktory

  NAME = 'Faktory'.freeze
  LICENSE = 'See LICENSE and the LGPL-3.0 for licensing details.'

  DEFAULTS = {
    queues: ['default'],
    concurrency: 10,
    require: '.',
    environment: 'development',
    # As of 2017, Heroku's process timeout is 30 seconds.
    # After 30 seconds, processes are KILLed so assume 25
    # seconds to gracefully shutdown and 5 seconds to hard
    # shutdown.
    timeout: 25,
    error_handlers: [],
    lifecycle_events: {
      startup: [],
      quiet: [],
      shutdown: [],
    },
    reloader: proc { |&block| block.call },
  }

  DEFAULT_JOB_OPTIONS = {
    'retry' => 25,
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
  #     config.worker_middleware do |chain|
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
    server_pool.with do |conn|
      yield conn
    end
  end

  def self.server_pool
    @pool ||= Faktory::Connection.create
  end

  def self.faktory=(hash)
    @pool = Faktory::Connection.create(hash)
  end

  def self.client_middleware
    @client_chain ||= Middleware::Chain.new
    yield @client_chain if block_given?
    @client_chain
  end

  def self.worker_middleware
    @worker_chain ||= Middleware::Chain.new
    yield @worker_chain if block_given?
    @worker_chain
  end

  def self.default_job_options=(hash)
    # stringify
    @default_job_options = default_job_options.merge(Hash[hash.map{|k, v| [k.to_s, v]}])
  end
  def self.default_job_options
    defined?(@default_job_options) ? @default_job_options : DEFAULT_JOB_OPTIONS
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

  def self.💃🕺(io = $stdout)
    colors = (31..37).to_a
    sz = colors.size
    "DANCE MODE ACTIVATED".chars.each_with_index do |chr, idx|
      io.print("\e[#{colors[rand(sz)]};1m#{chr}")
    end
    io.print("\e[0m\n")
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
