require 'helper'

class ClientFaktory < Minitest::Test
  def teardown
    # Ensure that these tests aren't dependent on run order
    ENV["FAKTORY_PROVIDER"] = nil
    ENV["FAKTORY_URL"] = nil
  end

  def test_client_initialized_with_default_url
    client = Faktory::Client.new
    assert_equal URI("tcp://localhost:7419"), client.instance_variable_get(:@location)
  end

  def test_client_initialized_with_default_timeout
    client = Faktory::Client.new
    assert_equal Faktory::Client::DEFAULT_TIMEOUT, client.instance_variable_get(:@timeout)
  end

  def test_client_initialized_with_specific_timeout
    client = Faktory::Client.new(timeout: 0.1)
    assert_equal 0.1, client.instance_variable_get(:@timeout)
  end

  def test_client_initialized_with_env
    ENV["FAKTORY_PROVIDER"] = "FAKTORY_URL"
    ENV["FAKTORY_URL"] = "tcp://127.0.0.1:7419"

    client = Faktory::Client.new
    assert_equal URI("tcp://127.0.0.1:7419"), client.instance_variable_get(:@location)
  end

  def test_client_initialized_with_specific_url
    ENV["FAKTORY_PROVIDER"] = "FAKTORY_URL"
    ENV["FAKTORY_URL"] = "tcp://127.0.0.1:7419"

    client = Faktory::Client.new(url: 'tcp://localhost:7419')
    assert_equal URI("tcp://localhost:7419"), client.instance_variable_get(:@location)
  end
end
