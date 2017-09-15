require 'helper'

class SystemTest < Minitest::Test
  def randjob(idx)
    {
      jid: "1231278127839" + idx.to_s,
      queue: "default",
      jobtype:  "SomeJob",
      args:  [1, "string", 3],
    }
  end

  def test_system
    threads = []
    3.times do |ix|
      threads << Thread.new do
        client = Faktory::Client.new

        #puts "Pushing"
        100.times do |idx|
          client.push(randjob((ix*100)+idx))
        end

        #puts "Popping"
        100.times do |idx|
          job = client.fetch("default")
          refute_nil job
          if idx % 100 == 99
            client.fail(job["jid"], RuntimeError.new("oops"))
          else
            client.ack(job["jid"])
          end
        end

      end
    end

    threads.each(&:join)
  end
end
