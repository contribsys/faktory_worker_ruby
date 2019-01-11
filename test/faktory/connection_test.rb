require 'helper'

class ConnectionFaktory < Minitest::Test
  def teardown
    # Ensure that these tests aren't dependent on run order
    ENV["FAKTORY_PROVIDER"] = nil
    ENV["FAKTORY_URL"] = nil
  end

  def test_connection_initialized_with_default_url
    pool = Faktory::Connection.create
    pool.with do |client|
      assert_equal URI("tcp://localhost:7419"), client.instance_variable_get(:@location)
    end
  end

  def test_connection_initialized_with_env
    ENV["FAKTORY_PROVIDER"] = "FAKTORY_URL"
    ENV["FAKTORY_URL"] = "tcp://127.0.0.1:7419"

    pool = Faktory::Connection.create
    pool.with do |client|
      assert_equal URI("tcp://127.0.0.1:7419"), client.instance_variable_get(:@location)
    end
  end

  def test_connection_initialized_with_specific_url
    ENV["FAKTORY_PROVIDER"] = "FAKTORY_URL"
    ENV["FAKTORY_URL"] = "tcp://127.0.0.1:7419"

    pool = Faktory::Connection.create(url: 'tcp://localhost:7419')
    pool.with do |client|
      assert_equal URI("tcp://localhost:7419"), client.instance_variable_get(:@location)
    end
  end
end