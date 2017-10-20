require 'socket'
require 'json'
require 'uri'
require 'securerandom'

module Faktory
  class CommandError < StandardError;end
  class ParseError < StandardError;end

  class Client
    @@random_process_wid = SecureRandom.hex(8)

    attr_accessor :middleware

    # Best practice is to rely on the localhost default for development
    # and configure the environment variables for non-development environments.
    #
    # FAKTORY_PROVIDER=MY_FAKTORY_URL
    # MY_FAKTORY_URL=tcp://:somepass@my-server.example.com:7419
    #
    # Note above, the URL can contain the password for secure installations.
    def initialize(url: 'tcp://localhost:7419', debug: false)
      @debug = debug
      @location = uri_from_env || URI(url)
      open
    end

    def close
      return unless @sock
      command "END"
      @sock.close
      @sock = nil
    end

    # Warning: this clears all job data in Faktory
    def flush
      transaction do
        command "FLUSH"
        ok!
      end
    end

    def push(job)
      transaction do
        command "PUSH", JSON.generate(job)
        ok!
        job["jid"]
      end
    end

    def fetch(*queues)
      job = nil
      transaction do
        command("FETCH", *queues)
        job = result
      end
      JSON.parse(job) if job
    end

    def ack(jid)
      transaction do
        command("ACK", %Q[{"jid":"#{jid}"}])
        ok!
      end
    end

    def fail(jid, ex)
      transaction do
        command("FAIL", JSON.dump({ message: ex.message[0...1000],
                          errtype: ex.class.name,
                          jid: jid,
                          backtrace: ex.backtrace}))
        ok!
      end
    end

    # Sends a heartbeat to the server, in order to prove this
    # worker process is still alive.
    #
    # Return a string signal to process, legal values are "quiet" or "terminate".
    # The quiet signal is informative: the server won't allow this process to FETCH
    # any more jobs anyways.
    def beat
      transaction do
        command("BEAT", %Q[{"wid":"#{@@random_process_wid}"}])
        str = result
        if str == "OK"
          str
        else
          hash = JSON.parse(str)
          hash["signal"]
        end
      end
    end

    def info
      transaction do
        command("INFO")
        str = result
        JSON.parse(str) if str
      end
    end

    private

    def debug(line)
      puts line
    end

    def tls?
      @location.hostname !~ /\Alocalhost\z/ || @location.scheme =~ /tls/
    end

    def open
      if tls?
        sock = TCPSocket.new(@location.hostname, @location.port)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.set_params(verify_mode: OpenSSL::SSL::VERIFY_PEER)
        ctx.ssl_version = :TLSv1_2

        @sock = OpenSSL::SSL::SSLSocket.new(sock, ctx).tap do |socket|
          socket.sync_close = true
          socket.connect
        end
      else
        @sock = TCPSocket.new(@location.hostname, @location.port)
        @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
      end

      payload = {
        "wid": @@random_process_wid,
        "hostname": Socket.gethostname,
        "pid": $$,
        "labels": ["ruby-#{RUBY_VERSION}"],
      }

      hi = result

      if hi =~ /\AHI (.*)/
        hash = JSON.parse($1)
        # TODO verify version tag
        salt = hash["s"]
        if salt
          pwd = @location.password
          if !pwd
            raise ArgumentError, "Server requires password, but none has been configured"
          end
          payload["pwdhash"] = Digest::SHA256.hexdigest(pwd + salt)
        end
      end

      command("HELLO", JSON.dump(payload))
      ok!
    end

    def command(*args)
      cmd = args.join(" ")
      @sock.puts(cmd)
      debug "> #{cmd}" if @debug
    end

    def transaction
      retryable = true
      begin
        yield
      rescue Errno::EPIPE, Errno::ECONNRESET
        if retryable
          retryable = false
          open
          retry
        else
          raise
        end
      end
    end

    # I love pragmatic, simple protocols.  Thanks antirez!
    # https://redis.io/topics/protocol
    def result
      line = @sock.gets
      debug "< #{line}" if @debug
      raise Errno::ECONNRESET, "No response" unless line
      chr = line[0]
      if chr == '+'
        line[1..-1].strip
      elsif chr == '$'
        count = line[1..-1].strip.to_i
        data = nil
        data = @sock.read(count) if count > 0
        line = @sock.gets
        data
      elsif chr == '-'
        raise CommandError, line[1..-1]
      else
        # this is bad, indicates we need to reset the socket
        # and start fresh
        raise ParseError, line.strip
      end
    end

    def ok!
      resp = result
      raise CommandError, resp if resp != "OK"
      true
    end

    # FAKTORY_PROVIDER=MY_FAKTORY_URL
    # MY_FAKTORY_URL=tcp://:some-pass@some-hostname:7419
    def uri_from_env
      prov = ENV['FAKTORY_PROVIDER']
      return nil unless prov
      raise(ArgumentError, <<-EOM) if prov.index(":")
Invalid FAKTORY_PROVIDER '#{prov}', it should be the name of the ENV variable that contains the URL
    FAKTORY_PROVIDER=MY_FAKTORY_URL
    MY_FAKTORY_URL=tcp://:some-pass@some-hostname:7419
EOM
      val = ENV[prov]
      return URI(val) if val

      val = ENV['FAKTORY_URL']
      return URI(val) if val
      nil
    end

  end
end

