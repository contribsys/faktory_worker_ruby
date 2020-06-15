
# this is the necessary magic to get a line-oriented protocol to
# respect a read timeout. unfortunately Ruby sockets do not provide any
# timeout support directly, delegating that to the IO reactor.
module Faktory
  class TimeoutError < Timeout::Error; end

  module ReadTimeout
    CRLF = "\r\n"
    BUFSIZE = 16_384

    # Ruby's TCP sockets do not implement timeouts.
    # We have to implement them ourselves by using
    # nonblocking IO and IO.select.
    def initialize(**opts)
      @buf = "".dup
      @timeout = opts[:timeout] || 5
    end

    def gets
      while (crlf = @buf.index(CRLF)).nil?
        @buf << read_timeout(BUFSIZE)
      end

      @buf.slice!(0, crlf + 2)
    end

    def read(nbytes)
      result = @buf.slice!(0, nbytes)
      result << read_timeout(nbytes - result.bytesize) while result.bytesize < nbytes
      result
    end

    private
    def read_timeout(nbytes)
      loop do
        result = @sock.read_nonblock(nbytes, exception: false)
        if result == :wait_readable
          raise Faktory::TimeoutError unless IO.select([@sock], nil, nil, @timeout)
        elsif result == :wait_writable
          raise Faktory::TimeoutError unless IO.select(nil, [@sock], nil, @timeout)
        elsif result == nil
          raise Errno::ECONNRESET
        else
          return result
        end
      end
    end
  end
end
