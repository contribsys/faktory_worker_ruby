# frozen_string_literal: true
require 'faktory'

module Faktory
  module ExceptionHandler

    class Logger
      def call(ex, ctxHash)
        Faktory.logger.warn(Faktory.dump_json(ctxHash)) if !ctxHash.empty?
        Faktory.logger.warn "#{ex.class.name}: #{ex.message}"
        Faktory.logger.warn ex.backtrace.join("\n") unless ex.backtrace.nil?
      end

      # Set up default handler which just logs the error
      Faktory.error_handlers << Faktory::ExceptionHandler::Logger.new
    end

    def handle_exception(ex, ctxHash={})
      Faktory.error_handlers.each do |handler|
        begin
          handler.call(ex, ctxHash)
        rescue => ex
          Faktory.logger.error "!!! ERROR HANDLER THREW AN ERROR !!!"
          Faktory.logger.error ex
          Faktory.logger.error ex.backtrace.join("\n") unless ex.backtrace.nil?
        end
      end
    end

  end
end
