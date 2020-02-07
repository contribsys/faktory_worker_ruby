module Faktory
  module Trackable

    ##
    # Tracking allows a long-running Faktory job to report its progress:
    #
    #   def perform(...)
    #     track_progress(10, "Calculating values")
    #     # do some work
    #
    #     track_progress(20, "Sending emails")
    #     # do some more work
    #
    #     track_progress(20, "Sending emails", reserve_until: 10.minutes.from_now)
    #     # do some more work
    #   end
    #
    # Note:
    # 1. jobs should be small and fine-grained (and so fast) if possible.
    # 2. tracking is useful for long-running jobs, tracking a fast job will only add overhead
    # 3. tracking only works with a single job, use Batches to monitor a group of jobs
    # 4. reserve_until allows a job to dynamically extend its reservation so it is not garbage collected by Faktory while running
    # 5. you can only reserve up to 24 hours.
    #
    def track_progress(percent, desc=nil, reserve_until:nil)
      hash = { 'jid' => jid, 'percent' => percent.to_i, 'desc' => desc }
      hash["reserve_until"] = convert(reserve_until) if reserve_until
      Faktory.server {|c| c.set_track(hash) }
    end

    private

    def convert(ts)
      raise ArgumentError, "Timestamp in the past: #{ts}" if Time.now > ts
      raise ArgumentError, "Timestamp too far in the future: #{ts}" if (Time.now + 86400) < ts

      tsf = ts.to_f
      Time.at(tsf).utc.iso8601
    end
  end
end
