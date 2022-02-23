require "helper"
require "faktory/mutate"

class MutateTest < LiveTest
  class MutateJob
    include Faktory::Job
    def perform(arg)
    end
  end

  def test_clear
    cl = Faktory::Client.new
    cl.flush

    data = cl.info
    assert_equal 0, data.dig("faktory", "tasks", "Scheduled", "size")

    MutateJob.perform_in(12.minutes, 1)
    data = cl.info
    assert_equal 1, data["faktory"]["tasks"]["Scheduled"]["size"]

    cl.clear(Faktory::SCHEDULED)
    data = cl.info
    assert_equal 0, data["faktory"]["tasks"]["Scheduled"]["size"]
  end

  def test_discard
    cl = Faktory::Client.new
    cl.flush

    data = cl.info
    assert_equal 0, data.dig("faktory", "tasks", "Scheduled", "size")

    MutateJob.perform_in(12.minutes, "elephant")
    MutateJob.perform_in(13.minutes, "zebra")
    data = cl.info
    assert_equal 2, data["faktory"]["tasks"]["Scheduled"]["size"]

    cl.discard(Faktory::SCHEDULED) do |jobs|
      jobs.with_type(MutateJob)
      jobs.matching("*elephant*")
    end

    data = cl.info
    assert_equal 1, data["faktory"]["tasks"]["Scheduled"]["size"]

    cl.discard(Faktory::SCHEDULED)

    data = cl.info
    assert_equal 0, data["faktory"]["tasks"]["Scheduled"]["size"]
  end
end
