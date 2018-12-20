# frozen_string_literal: true

require 'active_job'

module ActiveJob
  module QueueAdapters
    # == Faktory adapter for Active Job
    #
    # To use Faktory set the queue_adapter config to +:faktory+.
    #
    #   Rails.application.config.active_job.queue_adapter = :faktory
    class FaktoryAdapter
      def enqueue(job) #:nodoc:
        enqueue_at(job, nil)
      end

      def enqueue_at(job, timestamp) #:nodoc:
        jid = SecureRandom.hex(12)
        job.provider_job_id = jid
        hash = {
          "jid"     => jid,
          "jobtype" => JobWrapper.to_s,
          "custom"  => {
            "wrapped" => job.class.to_s,
          },
          "queue"   => job.queue_name,
          "args"    => [ job.serialize ],
        }
        opts = job.faktory_options_hash.dup
        hash["at"] = Time.at(timestamp).utc.to_datetime.rfc3339(9) if timestamp
        if opts.size > 0
          hash["retry"] = opts.delete("retry") if opts.has_key?("retry")
          hash["custom"] = opts.merge(hash["custom"])
        end
        # Faktory::Client does not support symbols as keys
        Faktory::Client.new.push(hash)
      end

      class JobWrapper #:nodoc:
        include Faktory::Job

        def perform(job_data)
          Base.execute job_data
        end
      end
    end
  end

  class Base
    class_attribute :faktory_options_hash
    self.faktory_options_hash = {}

    def self.faktory_options(hsh)
      self.faktory_options_hash = self.faktory_options_hash.stringify_keys.merge(hsh.stringify_keys)
    end
  end
end
