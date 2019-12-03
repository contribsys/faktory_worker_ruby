require 'helper'

class BatchTest < Minitest::Test
  def setup
    Faktory.server{|c| c.flush}
  end

  class BatchJob
    include Faktory::Job
    def perform(*)
    end
  end

  class FooJob
    include Faktory::Job
    def perform(*)
    end
  end

  class BarJob
    include Faktory::Job
    def perform(*)
    end
  end

  def test_basic_definition
    skip "requires Faktory Enterprise" unless ent?

    b = Faktory::Batch.new
    refute b.bid
    b.success = FooJob.to_s
    b.jobs do
      BatchJob.perform_async
    end
    assert b.bid

    # verify and execute the batch's job
    job = pop("default")
    assert job
    assert_equal BatchJob.to_s, job["jobtype"]
    assert_equal b.bid, job.dig("custom", "bid")
    ack job

    job = pop("default")
    assert job
    assert_equal FooJob.to_s, job["jobtype"]
    refute job.dig("custom", "bid")
    ack job
  end

  def test_nested_definition
    skip "requires Faktory Enterprise" unless ent?
    b = Faktory::Batch.new
    refute b.bid

    pbid = nil
    cbid = nil

    b.success = FooJob.to_s
    b.jobs do |parent|
      pbid = parent.bid

      BatchJob.perform_async

      child = Faktory::Batch.new
      child.parent_bid = parent.bid
      child.success = BarJob.to_s
      child.jobs do
        BatchJob.perform_async
      end
      cbid = child.bid
    end
    assert pbid
    assert cbid

    st = Faktory::BatchStatus.new(pbid)
    assert_equal 1, st.total
    assert_equal 1, st.pending
    refute st.parent_bid

    st = Faktory::BatchStatus.new(cbid)
    assert_equal 1, st.total
    assert_equal 1, st.pending
    assert st.parent_bid


    # verify and execute the batch's job
    job = pop("default")
    assert job
    assert_equal BatchJob.to_s, job["jobtype"]
    assert_equal pbid, job.dig("custom", "bid")
    ack job

    job = pop("default")
    assert job
    assert_equal BatchJob.to_s, job["jobtype"]
    assert_equal cbid, job.dig("custom", "bid")
    ack job

    job = pop("default")
    assert job
    assert_equal BarJob.to_s, job["jobtype"]
    refute job.dig("custom", "bid")
    ack job

    job = pop("default")
    assert job
    assert_equal FooJob.to_s, job["jobtype"]
    refute job.dig("custom", "bid")
    ack job
  end

  def ack(job)
    Faktory.server do |client|
      client.ack job["jid"]
    end
  end

  def pop(queue)
    Faktory.server do |client|
      client.fetch queue
    end
  end
end
