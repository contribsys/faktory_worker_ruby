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

    it 'perform_async' do
      Faktory::Job.perform_async('someFunc')
      assert_equal 1, Faktory::Queues['default'].size

      job = Faktory::Queues['default'].last
      assert_equal 'someFunc', job['jobtype']
      assert_equal [], job['args']

      Faktory::Job.perform_async('someFunc', ['some', 'args'], queue: 'some_q')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].last
      assert_equal 'someFunc', job['jobtype']
      assert_equal ['some', 'args'], job['args']
    end

    it 'perform_in' do
      Faktory::Job.perform_in(10, 'someFunc')
      assert_equal 1, Faktory::Queues['default'].size

      job = Faktory::Queues['default'].last
      assert_equal 'someFunc', job['jobtype']
      assert_equal [], job['args']
      assert_in_delta Time.now.to_f, Time.parse(job['at']).to_f, 10.1


      Faktory::Job.perform_in(10, 'someFunc', ['some', 'args'], queue: 'some_q')
      assert_equal 1, Faktory::Queues['some_q'].size

      job = Faktory::Queues['some_q'].first
      assert_equal 'someFunc', job['jobtype']
      assert_equal 'some_q', job['queue']
      assert_equal ['some', 'args'], job['args']
      assert_in_delta Time.now.to_f, Time.parse(job['at']).to_f, 10.1
    end
  end
end
