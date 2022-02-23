require "helper"

class SystemTest < LiveTest
  def around
    # We reset the pool since we're switching back and forth between test/non-test mode,
    # within the FWR test suite and the pool may or may not be useable for live tests
    # depending on the order of the execution of test cases.
    Faktory.instance_variable_set(:@pool, nil)
    Faktory.server { |s| s.flush }
    super
  end

  def randjob(idx)
    {
      jid: "1231278127839" + idx.to_s,
      queue: "default",
      jobtype: "SomeJob",
      args: [1, "string", 3]
    }
  end

  def test_system
    threads = []
    3.times do |ix|
      threads << Thread.new do
        client = Faktory::Client.new

        # puts "Pushing"
        100.times do |idx|
          client.push(randjob((ix * 100) + idx))
        end

        # puts "Popping"
        100.times do |idx|
          job = client.fetch("default")
          refute_nil job
          if idx % 100 == 99
            client.fail(job["jid"], RuntimeError.new("oops"))
          else
            client.ack(job["jid"])
          end
        end
      end
    end

    threads.each(&:join)
  end

  class TestJob
    include Faktory::Job
    faktory_options retry: 3, backtrace: 10, blargh: "foo", queue: "custom"

    def perform(count, name)
    end
  end

  def test_job
    require "faktory/middleware/i18n"

    jid = TestJob.perform_async(1, "bob")
    refute_nil jid
    assert_equal 24, jid.size

    payload = Faktory.server { |c| c.fetch("custom") }
    assert_equal "en", payload.dig("custom", "locale")
  end

  def test_job_at
    jid = TestJob.set(queue: "another").perform_in(10, 1, "bob")
    refute_nil jid
    assert_equal 24, jid.size
  end
end
