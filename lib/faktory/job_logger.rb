module Faktory
  class JobLogger

    def call(item)
      start = Time.now
      logger.info("start".freeze)
      yield
      logger.info("done: #{elapsed(start)} sec")
    rescue Exception
      logger.info("fail: #{elapsed(start)} sec")
      raise
    end

    private

    def elapsed(start)
      (Time.now - start).round(3)
    end

    def logger
      Faktory.logger
    end
  end
end
