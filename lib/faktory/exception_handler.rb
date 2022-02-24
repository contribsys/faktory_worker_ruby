# frozen_string_literal: true

require "faktory"

module Faktory
  module ExceptionHandler
    class Logger
      def call(ex, ctx_hash)
        Faktory.logger.warn(Faktory.dump_json(ctx_hash)) if !ctx_hash.empty?
        Faktory.logger.warn "#{ex.class.name}: #{ex.message}"
        Faktory.logger.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      end

      # Set up default handler which just logs the error
      Faktory.error_handlers << Faktory::ExceptionHandler::Logger.new
    end

    def handle_exception(ex, ctx_hash = {})
      Faktory.error_handlers.each do |handler|
        handler.call(ex, ctx_hash)
      rescue => ex
        Faktory.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
        Faktory.logger.error ex
        Faktory.logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
      end
    end
  end
end
