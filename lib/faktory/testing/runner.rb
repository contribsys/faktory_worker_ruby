module Faktory
  module Testing
    class Runner
      def initialize(job)
        self.job_class = job['jobtype']
        self.arguments = job['args']
      end

      def push
        unless Faktory::Testing.inline?
          # do nothing when mode is fake or disable
          return
        end

        job_class.new.perform(*arguments)
      end

      def job_class
        @job_class
      end

      def job_class=(klass)
        @job_class = klass
      end

      def arguments
        @arguments
      end

      def arguments=(args)
        @arguments = args
      end
    end
  end
end
