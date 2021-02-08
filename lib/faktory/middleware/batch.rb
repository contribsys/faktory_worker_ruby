# frozen_string_literal: true
#
# Simple middleware to save the current batch and restore it when the job executes.
#
module Faktory::Middleware::Batch
  class Client
    def call(payload, pool)
      b = Thread.current[:faktory_batch]
      if b
        payload["custom"] ||= {}
        payload["custom"]["bid"] = b.bid
      end
      yield
    end
  end

  class Worker
    def call(jobinst, payload)
      jobinst.bid = payload.dig("custom", "bid")
      yield
    end
  end
end

Faktory.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Faktory::Middleware::Batch::Client
  end
end

Faktory.configure_worker do |config|
  config.client_middleware do |chain|
    chain.add Faktory::Middleware::Batch::Client
  end
  config.worker_middleware do |chain|
    chain.add Faktory::Middleware::Batch::Worker
  end
end
