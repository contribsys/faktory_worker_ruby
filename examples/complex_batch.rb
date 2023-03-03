# This file gives you an example of complex workflow processing with
# Faktory Enterprise's batch feature. This reimplements Sidekiq's example
# here: https://github.com/sidekiq/sidekiq/wiki/Really-Complex-Workflows-with-Batches

# probably don't want this in production
Faktory::Client.new.flush

# Run this file against a Faktory Enterprise instance and it should execute
# the workflow as defined below.

=begin # rubocop:disable Style/BlockComments

% bundle exec faktory-worker -r ./examples/complex_batch.rb
2023-03-03T01:48:20.972Z 67006 TID-1f4 INFO: Running in ruby 3.2.0 (2022-12-25 revision a528908271) [arm64-darwin22]
2023-03-03T01:48:20.972Z 67006 TID-1f4 INFO: See LICENSE and the LGPL-3.0 for licensing details.
2023-03-03T01:48:20.972Z 67006 TID-1f4 INFO: Starting processing, hit Ctrl-C to stop
2023-03-03T01:48:20.983Z 67006 TID-1l8 OverallWorkflow JID-aaff1208622d39bb2d89b00c INFO: start
2023-03-03T01:48:20.984Z 67006 TID-1l8 OverallWorkflow JID-aaff1208622d39bb2d89b00c INFO: Creating workflow b-W5uwOl0DNxfZyg for user 1234
2023-03-03T01:48:20.984Z 67006 TID-1ls A JID-3e111d35a7b3bee3ac4966b2 INFO: start
2023-03-03T01:48:20.984Z 67006 TID-1ls A JID-3e111d35a7b3bee3ac4966b2 INFO: A running: nil
2023-03-03T01:48:20.984Z 67006 TID-1ls A JID-3e111d35a7b3bee3ac4966b2 INFO: done: 0.0 sec
2023-03-03T01:48:20.985Z 67006 TID-1l8 OverallWorkflow JID-aaff1208622d39bb2d89b00c INFO: done: 0.001 sec
2023-03-03T01:48:20.985Z 67006 TID-1mc Step1Done JID-e59a07e4ec286d8f3a13a216 INFO: start
2023-03-03T01:48:20.986Z 67006 TID-1mw B JID-90b811445b4ba7de3e0e6e7c INFO: start
2023-03-03T01:48:20.986Z 67006 TID-1mw B JID-90b811445b4ba7de3e0e6e7c INFO: B running: nil
2023-03-03T01:48:20.986Z 67006 TID-1mw B JID-90b811445b4ba7de3e0e6e7c INFO: done: 0.0 sec
2023-03-03T01:48:20.986Z 67006 TID-1ng C JID-8c585cd21941a5c1bac13871 INFO: start
2023-03-03T01:48:20.986Z 67006 TID-1ng C JID-8c585cd21941a5c1bac13871 INFO: C running: "1234"
2023-03-03T01:48:20.986Z 67006 TID-1ng C JID-8c585cd21941a5c1bac13871 INFO: done: 0.0 sec
2023-03-03T01:48:20.986Z 67006 TID-1mc Step1Done JID-e59a07e4ec286d8f3a13a216 INFO: done: 0.001 sec
2023-03-03T01:48:20.987Z 67006 TID-1o0 Step2Done JID-624794671f07dfb54d2ee423 INFO: start
2023-03-03T01:48:20.988Z 67006 TID-1ok H JID-0ce36787e93e7a643cf7c571 INFO: start
2023-03-03T01:48:20.988Z 67006 TID-1ok H JID-0ce36787e93e7a643cf7c571 INFO: H running: nil
2023-03-03T01:48:20.988Z 67006 TID-1ok H JID-0ce36787e93e7a643cf7c571 INFO: done: 0.0 sec
2023-03-03T01:48:20.988Z 67006 TID-1p4 I JID-0de083dfc4d552635a386d6c INFO: start
2023-03-03T01:48:20.988Z 67006 TID-1p4 I JID-0de083dfc4d552635a386d6c INFO: I running: nil
2023-03-03T01:48:20.988Z 67006 TID-1p4 I JID-0de083dfc4d552635a386d6c INFO: done: 0.0 sec
2023-03-03T01:48:20.988Z 67006 TID-1o0 Step2Done JID-624794671f07dfb54d2ee423 INFO: done: 0.001 sec
2023-03-03T01:48:20.989Z 67006 TID-1po NoOp JID-766b5e4564417e2861f393d2 INFO: start
2023-03-03T01:48:20.989Z 67006 TID-1po NoOp JID-766b5e4564417e2861f393d2 INFO: done: 0.0 sec
2023-03-03T01:48:20.989Z 67006 TID-1q8 Done JID-f3985f9e3bea52fa3ee2a616 INFO: start
2023-03-03T01:48:20.989Z 67006 TID-1q8 Done JID-f3985f9e3bea52fa3ee2a616 INFO: Done finished for user 1234
2023-03-03T01:48:20.989Z 67006 TID-1q8 Done JID-f3985f9e3bea52fa3ee2a616 INFO: done: 0.0 sec
=end

class OverallWorkflow
  include Faktory::Job

  def perform(uid)
    logger.info { "Creating workflow #{bid} for user #{uid}" }
    batch.jobs do
      step1 = Faktory::Batch.new
      step1.parent = batch
      step1.success = {jobtype: Step1Done, args: [uid]}
      step1.jobs do
        A.perform_async
      end
    end
  end
end

class A
  include Faktory::Job
  def perform(arg = nil)
    logger.info { "#{self.class.name} running: #{arg.inspect}" }
  end
end

class B < A; end

class C < A; end

class H < A; end

class I < A; end

# this is a callback which creates the jobs for Step 2
class Step1Done
  include Faktory::Job

  def perform(uid)
    # we want to reopen the parent batch and add a new
    # child batch which represents the next step.
    overall = parent_batch
    overall.jobs do
      step2 = Faktory::Batch.new
      step2.parent = overall
      step2.success = Step2Done
      step2.jobs do
        B.perform_async
        C.perform_async(uid)
      end
    end
  end
end

class Step2Done
  include Faktory::Job

  def perform
    # we want to reopen the parent batch and add a new
    # child batch which represents the next step.
    overall = parent_batch
    overall.jobs do
      step3 = Faktory::Batch.new
      step3.parent = overall
      step3.success = NoOp
      step3.jobs do
        H.perform_async
        I.perform_async
      end
    end
  end
end

class NoOp
  include Faktory::Job
  def perform
  end
end

class Done
  include Faktory::Job

  def perform(uid)
    logger.info { "#{self.class.name} finished for user #{uid}" }
  end
end

overall_batch = Faktory::Batch.new
overall_batch.success = {jobtype: Done, args: ["1234"]}
overall_batch.jobs do
  OverallWorkflow.perform_async("1234")
end
