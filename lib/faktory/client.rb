require 'socket'
require 'json'
require 'uri'
require 'digest'
require 'securerandom'

module Faktory
  class BaseError < StandardError; end
  class CommandError < BaseError; end
  class ParseError < BaseError; end

  # Faktory::Client provides a low-level connection to a Faktory server
  # and APIs which map to Faktory commands.
  #
  # Most APIs will return `true` if the operation succeeded or raise a
  # Faktory::BaseError if there was an unexpected error.
  class Client
    @@random_process_wid = ""

    DEFAULT_TIMEOUT = 5.0

    HASHER = proc do |iter, pwd, salt|
      sha = Digest::SHA256.new
      hashing = pwd + salt
      iter.times do
        hashing = sha.digest(hashing)
      end
      Digest.hexencode(hashing)
    end


    # Called when booting the worker process to signal that this process
    # will consume jobs and send BEAT.
    def self.worker!
      @@random_process_wid = SecureRandom.hex(8)
    end

    attr_accessor :middleware

    # Best practice is to rely on the localhost default for development
    # and configure the environment variables for non-development environments.
    #
    # FAKTORY_PROVIDER=MY_FAKTORY_URL
    # MY_FAKTORY_URL=tcp://:somepass@my-server.example.com:7419
    #
    # Note above, the URL can contain the password for secure installations.
    def initialize(url: uri_from_env || 'tcp://localhost:7419', debug: false, timeout: DEFAULT_TIMEOUT)
      @debug = debug
      @location = URI(url)
      @timeout = timeout

      open(@timeout)
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
        ok
      end
    end


    # Push a hash corresponding to a job payload to Faktory.
    # Hash must contain "jid", "jobtype" and "args" elements at minimum.
    # Returned value will either be the JID String if successful OR
    # a symbol corresponding to an error.
    def push(job)
      transaction do
        command "PUSH", JSON.generate(job)
        ok(job["jid"])
      end
    end

    # Returns either a job hash or falsy.
    def fetch(*queues)
      job = nil
      transaction do
        command("FETCH", *queues)
        job = result!
      end
      JSON.parse(job) if job
    end

    def ack(jid)
      transaction do
        command("ACK", %Q[{"jid":"#{jid}"}])
        ok
      end
    end

    def fail(jid, ex)
      transaction do
        command("FAIL", JSON.dump({ message: ex.message[0...1000],
                          errtype: ex.class.name,
                          jid: jid,
                          backtrace: ex.backtrace}))
        ok
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
        str = result!
        if str == "OK"
          str
        else
          hash = JSON.parse(str)
          hash["state"]
        end
      end
    end

    def info
      transaction do
        command("INFO")
        str = result!
        JSON.parse(str) if str
      end
    end

    private

    def debug(line)
      puts line
    end

    def tls?
      # Support TLS with this convention: "tcp+tls://:password@myhostname:port/"
      @location.scheme =~ /tls/
    end

    def open(timeout = DEFAULT_TIMEOUT)
      # this is the read/write timeout, not open.
      secs = Integer(timeout)
      usecs = Integer((timeout - secs) * 1_000_000)
      optval = [secs, usecs].pack("l_2")
      if tls?
        sock = TCPSocket.new(@location.hostname, @location.port)
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval)
        sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval)

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
        @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_RCVTIMEO, optval)
        @sock.setsockopt(Socket::SOL_SOCKET, Socket::SO_SNDTIMEO, optval)
      end

      payload = {
        "wid": @@random_process_wid,
        "hostname": Socket.gethostname,
        "pid": $$,
        "labels": Faktory.options[:labels] || ["ruby-#{RUBY_VERSION}"],
        "v": 2,
      }

      hi = result

      if hi =~ /\AHI (.*)/
        hash = JSON.parse($1)
        ver = hash["v"].to_i
        if ver > 2
          puts "Warning: Faktory server protocol #{ver} in use, this worker doesn't speak that version."
          puts "We recommend you upgrade this gem with `bundle up faktory_worker_ruby`."
        end

        salt = hash["s"]
        if salt
          pwd = @location.password
          if !pwd
            raise ArgumentError, "Server requires password, but none has been configured"
          end
          iter = (hash["i"] || 1).to_i
          raise ArgumentError, "Invalid hashing" if iter < 1

          payload["pwdhash"] = HASHER.(iter, pwd, salt)
        end
      end

      command("HELLO", JSON.dump(payload))
      ok
    end

    def command(*args)
      cmd = args.join(" ")
      @sock.puts(cmd)
      debug "> #{cmd}" if @debug
    end

    def transaction
      retryable = true

      # When using Faktory::Testing, you can get a client which does not actually
      # have an underlying socket.  Now if you disable testing and try to use that
      # client, it will crash without a socket.  This open() handles that case to
      # transparently open a socket.
      open(@timeout) if !@sock

      begin
        yield
      rescue Errno::EPIPE, Errno::ECONNRESET
        if retryable
          retryable = false
          open(@timeout)
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
        return nil if count == -1
        data = @sock.read(count) if count > 0
        line = @sock.gets # read extra linefeeds
        data
      elsif chr == '-'
        # Server can respond with:
        #
        # -ERR Something unexpected
        # We raise a CommandError
        #
        # -NOTUNIQUE Job not unique
        # We return ["NOTUNIQUE", "Job not unique"]
        err = line[1..-1].split(" ", 2)
        raise CommandError, err[1] if err[0] == "ERR"
        err
      else
        # this is bad, indicates we need to reset the socket
        # and start fresh
        raise ParseError, line.strip
      end
    end

    def ok(retval=true)
      resp = result
      return retval if resp == "OK"
      return resp[0].to_sym
    end

    def result!
      resp = result
      return nil if resp == nil
      raise CommandError, resp[0] if !resp.is_a?(String)
      resp
    end

    # FAKTORY_PROVIDER=MY_FAKTORY_URL
    # MY_FAKTORY_URL=tcp://:some-pass@some-hostname:7419
    def uri_from_env
      prov = ENV['FAKTORY_PROVIDER']
      if prov
        raise(ArgumentError, <<-EOM) if prov.index(":")
  Invalid FAKTORY_PROVIDER '#{prov}', it should be the name of the ENV variable that contains the URL
      FAKTORY_PROVIDER=MY_FAKTORY_URL
      MY_FAKTORY_URL=tcp://:some-pass@some-hostname:7419
  EOM
        val = ENV[prov]
        return URI(val) if val
      end

      val = ENV['FAKTORY_URL']
      return URI(val) if val
      nil
    end

  end
end

