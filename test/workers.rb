require "faktory/job"

class SomeJob
  include Faktory::Job

  faktory_options queue: "high"

  def perform(*args)
    logger.info "working"
  end
end
