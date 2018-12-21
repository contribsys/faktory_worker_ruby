require 'helper'
require 'faktory/processor'

class TestProcessor < Minitest::Test
  class SomeJob
    include Faktory::Job
    def perform
    end
  end
  def test_process_job
    job = {
      'jid' => '1234abc',
      'jobtype' => SomeJob.to_s,
      'queue' => 'default',
      'args' => [],
    }
    uow = UnitOfTestWork.new(job)
    p = Faktory::Processor.new(Faktory)
    p.process(uow)
    assert uow.success?
    refute uow.failed?
  end

  UnitOfTestWork = Struct.new(:job) do
    def acknowledge
      @ack = true
    end

    def fail(ex)
      @failed = ex
    end

    def success?
      @ack
    end

    def failed?
      !!@failed
    end

    def error
      @failed
    end

    def jid
      job['jid']
    end
  end
end
