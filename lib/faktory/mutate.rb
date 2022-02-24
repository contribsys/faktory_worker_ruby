require "faktory/client"

##
#
# Faktory's MUTATE API allows you to scan the sorted sets
# within Redis (retries, scheduled, dead) and take action
# (delete, enqueue, kill) on entries.
#
# require 'faktory/mutate'
# cl = Faktory::Client.new
# cl.discard(Faktory::RETRIES) do |filter|
#   filter.with_type("QuickBooksSyncJob")
#   filter.matching("*uid:12345*"))
# end
module Faktory
  # Valid targets
  RETRIES = "retries"
  SCHEDULED = "scheduled"
  DEAD = "dead"

  module Mutator
    class Filter
      attr_accessor :hash

      def initialize
        @hash = {}
      end

      # This must be the exact type of the job, no pattern matching
      def with_type(jobtype)
        @hash[:jobtype] = jobtype
      end

      # This is a regexp that will be passed as is to Redis's SCAN.
      # Notably you should surround it with * to ensure it matches
      # substrings within the job payload.
      # See https://redis.io/commands/scan for details.
      def matching(regexp)
        @hash[:regexp] = regexp
      end

      # One or more JIDs to target:
      # filter.jids << 'abcdefgh1234'
      # filter.jids = ['abcdefgh1234', '1234567890']
      def jids
        @hash[:jids] ||= []
      end

      def jids=(ary)
        @hash[:jids] = Array(ary)
      end
    end

    def discard(target, &block)
      filter = Filter.new
      block&.call(filter)
      mutate("discard", target, filter)
    end

    def kill(target, &block)
      filter = Filter.new
      block&.call(filter)
      mutate("kill", target, filter)
    end

    def requeue(target, &block)
      filter = Filter.new
      block&.call(filter)
      mutate("requeue", target, filter)
    end

    def clear(target)
      mutate("discard", target, nil)
    end

    private

    def mutate(cmd, target, filter)
      payload = {cmd: cmd, target: target}
      payload[:filter] = filter.hash if filter && !filter.hash.empty?

      transaction do
        command("MUTATE", JSON.dump(payload))
        ok
      end
    end
  end
end

Faktory::Client.send(:include, Faktory::Mutator)
