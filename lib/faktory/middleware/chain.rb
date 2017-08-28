# frozen_string_literal: true
module Faktory
  # Middleware is code configured to run before/after
  # a job is processed.  It is patterned after Rack
  # middleware. Middleware exists for the client side
  # (pushing jobs to a queue) as well as the worker
  # side (when jobs are actually executed).
  #
  # To add middleware to run when a job is pushed to Faktory:
  #
  # Faktory.configure_client do |config|
  #   config.push_middleware do |chain|
  #     chain.add MyClientHook
  #   end
  # end
  #
  # To run middleware when a job is executed within the worker process,
  # add it to the exec_middleware:
  #
  # Faktory.configure_worker do |config|
  #   config.exec_middleware do |chain|
  #     chain.add MyServerHook
  #     chain.remove ActiveRecord
  #   end
  # end
  #
  # To insert immediately preceding another entry:
  #
  # Faktory.configure_client do |config|
  #   config.middleware do |chain|
  #     chain.insert_before ActiveRecord, MyClientHook
  #   end
  # end
  #
  # To insert immediately after another entry:
  #
  # Faktory.configure_client do |config|
  #   config.middleware do |chain|
  #     chain.insert_after ActiveRecord, MyClientHook
  #   end
  # end
  #
  # This is an example of a minimal worker middleware:
  #
  # class MyServerHook
  #   def call(worker_instance, job)
  #     puts "Before work"
  #     yield
  #     puts "After work"
  #   end
  # end
  #
  # This is an example of a minimal client middleware, note
  # the method must return the result or the job will not push
  # to Redis:
  #
  # class MyClientHook
  #   def call(job, conn_pool)
  #     puts "Before push"
  #     result = yield
  #     puts "After push"
  #     result
  #   end
  # end
  #
  module Middleware
    class Chain
      include Enumerable
      attr_reader :entries

      def initialize_copy(copy)
        copy.instance_variable_set(:@entries, entries.dup)
      end

      def each(&block)
        entries.each(&block)
      end

      def initialize
        @entries = []
        yield self if block_given?
      end

      def remove(klass)
        entries.delete_if { |entry| entry.klass == klass }
      end

      def add(klass, *args)
        remove(klass) if exists?(klass)
        entries << Entry.new(klass, *args)
      end

      def prepend(klass, *args)
        remove(klass) if exists?(klass)
        entries.insert(0, Entry.new(klass, *args))
      end

      def insert_before(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || 0
        entries.insert(i, new_entry)
      end

      def insert_after(oldklass, newklass, *args)
        i = entries.index { |entry| entry.klass == newklass }
        new_entry = i.nil? ? Entry.new(newklass, *args) : entries.delete_at(i)
        i = entries.index { |entry| entry.klass == oldklass } || entries.count - 1
        entries.insert(i+1, new_entry)
      end

      def exists?(klass)
        any? { |entry| entry.klass == klass }
      end

      def retrieve
        map(&:make_new)
      end

      def clear
        entries.clear
      end

      def invoke(*args)
        chain = retrieve.dup
        traverse_chain = lambda do
          if chain.empty?
            yield
          else
            chain.shift.call(*args, &traverse_chain)
          end
        end
        traverse_chain.call
      end
    end

    class Entry
      attr_reader :klass

      def initialize(klass, *args)
        @klass = klass
        @args  = args
      end

      def make_new
        @klass.new(*@args)
      end
    end
  end
end
