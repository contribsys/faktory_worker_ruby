require 'helper'

class PolyglotTest < LiveTest
  describe 'jobs with non ruby class jobtype' do
    before do
      require 'faktory/testing'
      Faktory::Testing.fake!
    end

    after do
      Faktory::Testing.disable!
      Faktory::Queues.clear_all
    end

    SomePolyglotJob = Faktory::Job.set(queue: 'some_q', jobtype: 'someFunc')

    it 'perform_async' do
      Faktory::Job.set(queue: 'some_q', jobtype: 'someFunc').perform_async('some', 'args')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].last
      assert_equal 'someFunc', job['jobtype']
      assert_equal ['some', 'args'], job['args']
    end

    it 'perform_in' do
      Faktory::Job.set(queue: 'some_q', jobtype: 'someFunc').perform_in(10, 'some', 'args')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].first
      assert_equal 'someFunc', job['jobtype']
      assert_equal 'some_q', job['queue']
      assert_equal ['some', 'args'], job['args']
      assert_in_delta Time.now.to_f, Time.parse(job['at']).to_f, 10.1
    end

    it 'perform_async via constant' do
      SomePolyglotJob.perform_async('some', 'args')
      SomePolyglotJob.perform_async('some', 'args')

      assert_equal 2, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].last
      assert_equal 'someFunc', job['jobtype']
      assert_equal ['some', 'args'], job['args']

      assert Faktory::Queues['some_q'].first["jid"] != Faktory::Queues['some_q'].last["jid"]
    end
  end
end
