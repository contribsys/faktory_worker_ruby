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
  #   HardJob.perform_later(1, 2, 3)
  #
  # Note that perform_later is a class method, perform is an instance method.
  module Job
    attr_accessor :jid

    def self.included(base)
      raise ArgumentError, "You cannot include Faktory::Job in an ActiveJob: #{base.name}" if base.ancestors.any? {|c| c.name == 'ActiveJob::Base' }

      base.extend(ClassMethods)
      base.faktory_class_attribute :faktory_options_hash
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
        @opts['class'.freeze].client_push(@opts.merge!('args'.freeze => args))
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)

        @opts.merge! 'args'.freeze => args, 'at'.freeze => ts
        # Optimization to enqueue something now that is scheduled to go out now or in the past
        @opts.delete('at'.freeze) if ts <= now
        @opts['class'.freeze].client_push(@opts)
      end
      alias_method :perform_at, :perform_in
    end

    module ClassMethods

      def set(options)
        Setter.new(options.merge!('class'.freeze => self))
      end

      def perform_async(*args)
        client_push('class'.freeze => self, 'args'.freeze => args)
      end

      # +interval+ must be a timestamp, numeric or something that acts
      #   numeric (like an activesupport time interval).
      def perform_in(interval, *args)
        int = interval.to_f
        now = Time.now.to_f
        ts = (int < 1_000_000_000 ? now + int : int)

        item = { 'class'.freeze => self, 'args'.freeze => args, 'at'.freeze => ts }

        # Optimization to enqueue something now that is scheduled to go out now or in the past
        item.delete('at'.freeze) if ts <= now

        client_push(item)
      end
      alias_method :perform_at, :perform_in

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

      def client_push(item) # :nodoc:
        pool = Thread.current[:faktory_via_pool] || get_faktory_options['pool'.freeze] || Faktory.server_pool
        # stringify
        item.keys.each do |key|
          item[key.to_s] = item.delete(key)
        end

        pool.with {|c| c.push(item) }
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
