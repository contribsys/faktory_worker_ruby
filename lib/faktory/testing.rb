require 'faktory/testing/runner'

module Faktory
  module Testing
    def self.__test_mode
      @__test_mode
    end

    def self.__test_mode=(mode)
      @__test_mode = mode
    end

    def self.__set_test_mode(mode)
      if block_given?
        current_mode = self.__test_mode
        begin
          self.__test_mode = mode
          yield
        ensure
          self.__test_mode = current_mode
        end
      else
        self.__test_mode = mode
      end
    end

    def self.disable!(&block)
      __set_test_mode(:disable, &block)
    end

    def self.fake!(&block)
      __set_test_mode(:fake, &block)
    end

    def self.inline!(&block)
      # Don't allow blockless inline
      # https://github.com/mperham/sidekiq/issues/3495
      unless block_given?
        raise 'Must provide a block to Faktory::Testing.inline!'
      end

      __set_test_mode(:inline, &block)
    end

    def self.enabled?
      self.__test_mode != :disable
    end

    def self.disabled?
      self.__test_mode == :disable
    end

    def self.fake?
      self.__test_mode == :fake
    end

    def self.inline?
      self.__test_mode == :inline
    end
  end

  # Fake it 'til you make it by default
  Faktory::Testing.fake!

  class Client
    alias_method :real_push, :push
    alias_method :real_open, :open

    def push(job)
      if Faktory::Testing.enabled?
        Faktory::Testing::Runner.new(job).push
        return job['jid']
      else
        real_push(job)
      end
    end

    def open
      unless Faktory::Testing.enabled?
        real_open
      end
    end
  end
end
