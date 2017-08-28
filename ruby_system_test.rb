require 'socket'
require 'json'

module Faktory
  class CommandError < StandardError;end
  class ParseError < StandardError;end

  class Client
    def initialize(password:, format: 'json')
      @sock = TCPSocket.new("localhost", 7419)
      @sock.puts("AHOY pwd:#{password} format:#{format}")
      ok!
    end

    def close
      return unless @sock
      command "END"
      @sock.close
      @sock = nil
    end

    def push(job)
      command "PUSH", JSON.dump(job)
      ok!
    end

    def pop(queue)
      command("POP", queue)
      JSON.parse(result)
    end

    def ack(jid)
      command("ACK", jid)
      ok!
    end

    def fail(jid, ex)
      command("FAIL", JSON.dump({ jid: jid, message: ex.message,
                        errortype: ex.class.name,
                        backtrace: ex.backtrace}))
      ok!
    end

    private

    def command(*args)
      @sock.puts(args.join(" "))
    end

    def result
      line = @sock.gets
      case line[0]
      when '-'
        raise CommandError, line[1..-1]
      when '+'
        line[1..-1].strip
      when '$'
        count = line[1..-1].strip.to_i
        data = @sock.read(count)
        _ = @sock.gets
        data
      else
        # this is bad, indicates we need to reset the socket
        # and start fresh
        raise ParseError, line.strip
      end

      line
    end

    def ok!
      resp = result
      raise CommandError, resp if resp != "OK"
    end
  end
end

def randjob(idx)
  {
    jid: "1231278127839" + idx.to_s,
    queue: "default",
    jobtype:  "SomeJob",
    args:  [1, "string", 3],
  }
end

threads = []
3.times do |ix|
  threads << Thread.new do
    client = Faktory::Client.new(password: "123456")

    puts "Pushing"
    10000.times do |idx|
      client.push(randjob((ix*100)+idx))
    end

    puts "Popping"
    10000.times do |idx|
      job = client.pop("default")
      if idx % 100 == 99
        client.fail(job["jid"], RuntimeError.new("oops"))
      else
        client.ack(job["jid"])
      end
    end

  end
end

threads.each(&:join)
