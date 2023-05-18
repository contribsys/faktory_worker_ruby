require "helper"

class TrackingTest < Minitest::Test
  class TrackedJob
    include Faktory::Job
    faktory_options custom: {track: 1}
    def perform(*)
    end
  end

  include Faktory::Trackable

  # trackable needs a JID
  attr_reader :jid

  def test_job_tracking
    @jid = TrackedJob.perform_async(1)
    assert_equal String, @jid.class
    assert_equal 24, @jid.size

    cl = Faktory::Client.new

    ent_only do
      track_progress(1)
      track_progress(2, "Starting...")

      h = cl.get_track(@jid)
      assert_equal 2, h["percent"]
      assert_equal "Starting...", h["desc"]
      assert_equal "enqueued", h["state"]
      assert_equal @jid, h["jid"]
      cl.close

      assert_raises ArgumentError do
        track_progress(10, "Working...", reserve_until: 10.minutes)
      end

      assert_raises ArgumentError do
        track_progress(15, "Working...", reserve_until: 1.week.from_now)
      end

      track_progress(15, "Working...", reserve_until: 1.minute.from_now)
    end
  end
end
