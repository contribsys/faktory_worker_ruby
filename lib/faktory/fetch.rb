# frozen_string_literal: true
module Faktory
  UnitOfWork = Struct.new(:jid, :job) do
    def acknowledge
      Faktory.server {|c| c.ack(jid) }
    end

    def fail(ex)
      Faktory.server {|c| c.fail(jid, ex) }
    end
  end

  class Fetcher
    def initialize(options)
      @strictly_ordered_queues = !!options[:strict]
      @queues = options[:queues]
      @queues = @queues.uniq if @strictly_ordered_queues
    end

    def retrieve_work
      work = Faktory.server { |conn| conn.pop(*queues_cmd) }
      UnitOfWork.new(*work) if work
    end

    # Creating the pop command takes into account any
    # configured queue weights. By default pop returns
    # data from the first queue that has pending elements. We
    # recreate the queue command each time we invoke pop
    # to honor weights and avoid queue starvation.
    def queues_cmd
      if @strictly_ordered_queues
        @queues
      else
        @queues.shuffle.uniq
      end
    end

  end
end
