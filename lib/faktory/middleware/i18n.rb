# frozen_string_literal: true
#
# Simple middleware to save the current locale and restore it when the job executes.
# Use it by requiring it in your initializer:
#
#     require 'faktory/middleware/i18n'
#
module Faktory::Middleware::I18n
  # Get the current locale and store it in the message
  # to be sent to Faktory.
  class Client
    def call(job, pool)
      job['locale'] ||= I18n.locale
      yield
    end
  end

  # Pull the msg locale out and set the current thread to use it.
  class Server
    def call(worker, job)
      I18n.locale = job['locale'] || I18n.default_locale
      yield
    ensure
      I18n.locale = I18n.default_locale
    end
  end
end

Faktory.configure_client do |config|
  config.client_middleware do |chain|
    chain.add Faktory::Middleware::I18n::Client
  end
end

Faktory.configure_worker do |config|
  config.client_middleware do |chain|
    chain.add Faktory::Middleware::I18n::Client
  end
  config.server_middleware do |chain|
    chain.add Faktory::Middleware::I18n::Server
  end
end
