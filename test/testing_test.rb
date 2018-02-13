require 'helper'

class TestingTest < LiveTest
  describe 'faktory testing' do
    describe 'require/load faktory/testing.rb' do
      before do
        require 'faktory/testing'
      end

      after do
        Faktory::Testing.disable!
      end

      it 'enables fake testing' do
        Faktory::Testing.fake!
        assert Faktory::Testing.enabled?
        assert Faktory::Testing.fake?
        refute Faktory::Testing.inline?
      end

      it 'enables fake testing in a block' do
        Faktory::Testing.disable!
        assert Faktory::Testing.disabled?
        refute Faktory::Testing.fake?

        Faktory::Testing.fake! do
          assert Faktory::Testing.enabled?
          assert Faktory::Testing.fake?
          refute Faktory::Testing.inline?
        end

        refute Faktory::Testing.enabled?
        refute Faktory::Testing.fake?
      end

      it 'disables testing in a block' do
        Faktory::Testing.fake!
        assert Faktory::Testing.fake?

        Faktory::Testing.disable! do
          refute Faktory::Testing.fake?
          assert Faktory::Testing.disabled?
        end

        assert Faktory::Testing.fake?
        assert Faktory::Testing.enabled?
      end
    end
  end
end
