require "faktory/middleware/batch"

module Faktory
  ##
  # A Batch is a set of jobs which can be tracked as a group, with
  # callbacks that can fire after all the jobs are attempted or successful.
  # Every batch must define at least one callback.
  #
  # * The "complete" callback is fired when all jobs in the batch have been attempted.
  #   Some might have failed.
  # * The "success" callback is fired when all jobs in the batch have succeeded. This
  #   might never be fired if a job continues to error until it runs out of retries.
  #
  # **Please note that batches are only available in Faktory Enterprise.** This is
  # the client-side code required to implement batches, it won't work without
  # the server-side component.
  #
  # Simple example:
  #
  #   b = Faktory::Batch.new
  #   b.description = "Process all documents for user 12345"
  #   # a callback can be defined as just a Ruby job class
  #   b.success = "MySuccessCallbackJob"
  #   # or the full job hash...
  #   b.complete = { jobtype: "MyCompleteCallbackJob", args: [12345], queue: "critical" }
  #   b.jobs do
  #     SomeJob.perform_async(xyz)
  #     AnotherJob.perform_async(user_id)
  #   end
  #
  # At the end of the `jobs` call, the batch is persisted to the Faktory server. It must
  # not be modified further with one exception: jobs within the batch can "reopen" the batch
  # in order to dynamically add more jobs or child batches.
  #
  # Any job within a batch may "reopen" its own batch to dynamically add more jobs.
  # A job can get access to its batch by using the `bid` or `batch` accessor on
  # `Faktory::Job`. You can use the `bid` accessor to test if the job is part of a batch.
  #
  # Reopen example:
  #
  #  class MyJob
  #    include Faktory::Job
  #
  #    def perform
  #      batch.jobs do
  #        SomeOtherJob.perform_async
  #      end if bid
  #    end
  #
  # Batches may be nested without limit by setting `parent_bid` when creating a
  # batch. Generally you create child batches if you wish that subset of jobs to have
  # their own callback for your application logic purposes. Otherwise you can reopen the
  # current batch and add more jobs.
  #
  # Batch parent/child relationship is never implicit: you must manually set
  # `parent_bid` if you wish to define a child batch.
  #
  # Nested example:
  #
  #  class MyJob
  #    include Faktory::Job
  #
  #    def perform
  #      child = Faktory::Batch.new
  #
  #      # MyJob is executing as part of a previously defined batch.
  #      # Add a new child batch to this batch.
  #      child.parent_bid = bid
  #      child.success = ...
  #      child.jobs do |cb|
  #        SomeJob.perform_async
  #
  #        gchild = Faktory::Batch.new
  #        gchild.parent_bid = cb.bid
  #        gchild.success = ...
  #        gchild.jobs do |gcb|
  #          ChildJob.perform_async
  #        end
  #      end
  #    end
  #  end
  #
  # Callbacks are guaranteed to be called hierarchically: child's success callback
  # will not be called until gchild's success callback has executed successfully.
  #
  class Batch
    attr_reader :bid
    attr_accessor :description, :parent_bid

    def initialize(bid = nil)
      @bid = bid
    end

    def parent=(parent)
      @parent_bid = parent.bid
    end

    def success=(val)
      raise "Batch cannot be modified once created" if bid
      @success = to_callback(val)
    end

    def complete=(val)
      raise "Batch cannot be modified once created" if bid
      @complete = to_callback(val)
    end

    def jobs(&block)
      Faktory.server do |client|
        if @bid.nil?
          @bid = client.create_batch(self, &block)
        else
          client.reopen_batch(self, &block)
        end
      end
    end

    def to_h
      raise ArgumentError, "Callback required" unless defined?(@success) || defined?(@complete)

      hash = {}
      hash["parent_bid"] = parent_bid if parent_bid
      hash["description"] = description if description
      hash["success"] = @success if defined?(@success)
      hash["complete"] = @complete if defined?(@complete)
      hash
    end

    private

    def to_callback(val)
      case val
      when String
        basic_job.merge({"jobtype" => val})
      when Class
        basic_job.merge({"jobtype" => val})
      when Hash
        basic_job.merge(val)
      else
        raise ArgumentError, "Unknown callback #{val}"
      end
    end

    def basic_job
      {
        "jid" => SecureRandom.hex(12),
        "args" => [],
        "queue" => "default"
      }
    end
  end

  class BatchStatus
    def initialize(bid)
      @bid = bid
    end

    def hash
      @hash ||= Faktory.server { |c| c.batch_status(@bid) }
    end

    def created_at
      hash["created_at"]
    end

    def description
      hash["description"]
    end

    def parent_bid
      hash["parent_bid"]
    end

    def total
      hash["total"]
    end

    def pending
      hash["pending"]
    end
  end
end
