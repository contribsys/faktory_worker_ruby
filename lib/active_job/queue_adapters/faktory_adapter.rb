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
        jid = SecureRandom.hex(12)
        job.provider_job_id = jid
        # Faktory::Client does not support symbols as keys
        Faktory::Client.new.push \
          "jid"     => jid,
          "jobtype" => JobWrapper,
          "custom"  => {
            "wrapped" => job.class.to_s,
          },
          "priority" => job.priority,
          "queue"   => job.queue_name,
          "args"    => [ job.serialize ]
      end

      def enqueue_at(job, timestamp) #:nodoc:
        jid = SecureRandom.hex(12)
        job.provider_job_id = jid
        # Faktory::Client does not support symbols as keys
        Faktory::Client.new.push \
          "jid"     => jid,
          "jobtype" => JobWrapper,
          "custom"  => {
            "wrapped" => job.class.to_s
          },
          "priority" => job.priority,
          "queue"   => job.queue_name,
          "args"    => [ job.serialize ],
          "at"      => Time.at(timestamp).utc.to_datetime.rfc3339(9)
      end

      class JobWrapper #:nodoc:
        include Faktory::Job

        def perform(job_data)
          Base.execute job_data
        end
      end
    end
  end
end
