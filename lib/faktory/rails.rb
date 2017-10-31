# frozen_string_literal: true
module Faktory
  class Rails < ::Rails::Engine

    class Reloader
      def initialize(app = ::Rails.application)
        @app = app
      end

      def call
        @app.reloader.wrap do
          yield
        end
      end

      def inspect
        "#<Faktory::Rails::Reloader @app=#{@app.class.name}>"
      end
    end

    config.after_initialize do
      # This hook happens after all initializers are run, just before returning
      # from config/environment.rb back to faktory/cli.rb.
      # We have to add the reloader after initialize to see if cache_classes has
      # been turned on.
      #
      # None of this matters on the client-side, only within the Faktory executor itself.
      #
      Faktory.configure_client do |_|
        Faktory.options[:reloader] = Faktory::Rails::Reloader.new
      end
    end
  end if defined?(::Rails)
end
