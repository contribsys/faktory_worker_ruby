# frozen_string_literal: true
module Faktory

  ##
  # Include this module in your Job class and you can easily create
  # asynchronous jobs:
  #
  # class HardJob
  #   include Faktory::Job
  #
  #   def perform(*args)
  #     # do some work
  #   end
  # end
  #
  # Then in your Rails app, you can do this:
  #
  #   HardJob.perform_async(1, 2, 3)
  #
  # Note that perform_async is a class method, perform is an instance method.
  module Job
    attr_accessor :jid
    attr_accessor :bid

    def self.included(base)
      raise ArgumentError, "You cannot include Faktory::Job in an ActiveJob: #{base.name}" if base.ancestors.any? {|c| c.name == 'ActiveJob::Base' }

      base.extend(ClassMethods)
      base.faktory_class_attribute :faktory_options_hash
    end

    class << self
      # Low level helper to enqueue a job with any jobtype
      # +args+ must be an array of arguments
      #
      #   Faktory::Job.perform_async('someFunc', ["arg1"], queue: 'some_queue')
      #
      def perform_async(jobtype, args = [], faktory_options = Faktory.default_job_options)
        client_push({'jobtype'.freeze => jobtype, 'args'.freeze => args}, faktory_options)
      end

      # Low level helper to enqueue a job with any jobtype
      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      # +args+ must be an array of arguments
      #
      #   Faktory::Job.perform_in(12.minute, 'someFunc', ["arg1"], queue: 'some_queue')
      #
      def perform_in(interval, jobtype, args = [], faktory_options = Faktory.default_job_options)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)
        item = {'jobtype'.freeze => jobtype, 'args'.freeze => args}
        item['at'.freeze] = Time.at(ts).utc.to_datetime.rfc3339(9) if ts > now

        client_push(item, faktory_options)
      end
      alias_method :perform_at, :perform_in

      def client_push(item, faktory_options = Faktory.default_job_options) # :nodoc:
        pool = Thread.current[:faktory_via_pool] || faktory_options['pool'.freeze] || Faktory.server_pool
        item = faktory_options.merge(item)
        # stringify
        item.keys.each do |key|
          item[key.to_s] = item.delete(key)
        end
        item["jid"] ||= SecureRandom.hex(12)
        item["queue"] ||= "default"

        Faktory.client_middleware.invoke(item, pool) do
          pool.with do |c|
            c.push(item)
          end
        end
      end
    end

    def batch
      if bid
        @batch ||= Faktory::Batch.new(bid)
      end
    end

    def logger
      Faktory.logger
    end

    # This helper class encapsulates the set options for `set`, e.g.
    #
    #     SomeJob.set(queue: 'foo').perform_async(....)
    #
    class Setter
      def initialize(opts)
        @opts = opts
      end

      def perform_async(*args)
        @opts['jobtype'.freeze].client_push(@opts.merge!('args'.freeze => args))
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)
        at = Time.at(ts).utc.to_datetime.rfc3339(9)

        @opts.merge! 'args'.freeze => args, 'at'.freeze => at
        # Optimization to enqueue something now that is scheduled to go out now or in the past
        @opts.delete('at'.freeze) if ts <= now
        @opts['jobtype'.freeze].client_push(@opts)
      end
      alias_method :perform_at, :perform_in
    end

    module ClassMethods

      def set(options)
        Setter.new(options.merge!('jobtype'.freeze => self))
      end

      def perform_async(*args)
        Faktory::Job.perform_async(self, args, get_faktory_options)
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        Faktory::Job.perform_in(interval, self, args, get_faktory_options)
      end
      alias_method :perform_at, :perform_in

      def client_push(item) # :nodoc:
        Faktory::Job.client_push(item, get_faktory_options)
      end

      ##
      # Allows customization of Faktory features for this type of Job.
      # Legal options:
      #
      #   queue - use a named queue for this Job, default 'default'
      #   retry - enable automatic retry for this Job, *Integer* count, default 25
      #   backtrace - whether to save the error backtrace in the job payload to display in web UI,
      #      an integer number of lines to save, default *0*
      #
      def faktory_options(opts={})
        # stringify
        self.faktory_options_hash = get_faktory_options.merge(Hash[opts.map{|k, v| [k.to_s, v]}])
      end

      def get_faktory_options # :nodoc:
        self.faktory_options_hash ||= Faktory.default_job_options
      end

      def faktory_class_attribute(*attrs)
        instance_reader = true
        instance_writer = true

        attrs.each do |name|
          singleton_class.instance_eval do
            undef_method(name) if method_defined?(name) || private_method_defined?(name)
          end
          define_singleton_method(name) { nil }

          ivar = "@#{name}"

          singleton_class.instance_eval do
            m = "#{name}="
            undef_method(m) if method_defined?(m) || private_method_defined?(m)
          end
          define_singleton_method("#{name}=") do |val|
            singleton_class.class_eval do
              undef_method(name) if method_defined?(name) || private_method_defined?(name)
              define_method(name) { val }
            end

            if singleton_class?
              class_eval do
                undef_method(name) if method_defined?(name) || private_method_defined?(name)
                define_method(name) do
                  if instance_variable_defined? ivar
                    instance_variable_get ivar
                  else
                    singleton_class.send name
                  end
                end
              end
            end
            val
          end

          if instance_reader
            undef_method(name) if method_defined?(name) || private_method_defined?(name)
            define_method(name) do
              if instance_variable_defined?(ivar)
                instance_variable_get ivar
              else
                self.class.public_send name
              end
            end
          end

          if instance_writer
            m = "#{name}="
            undef_method(m) if method_defined?(m) || private_method_defined?(m)
            attr_writer name
          end
        end
      end

    end
  end
end
