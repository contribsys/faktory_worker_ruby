require 'helper'
require 'stringio'

class TestFaktory < Minitest::Test

  def test_dance_mode
    srand(1234)
    expected = "\e[34;1mD\e[37;1mA\e[36;1mN\e[35;1mC\e[35;1mE\e[31;1m \e[32;1mM\e[32;1mO\e[32;1mD\e[33;1mE\e[37;1m \e[34;1mA\e[37;1mC\e[35;1mT\e[35;1mI\e[33;1mV\e[37;1mA\e[33;1mT\e[31;1mE\e[31;1mD\e[0m\n"
    io = StringIO.new

    Faktory.💃🕺(io)

    assert_equal expected, io.string
  end

  def test_password_hashing
    iter = 1545
    pwd = "foobar"
    salt = "55104dc76695721d"
    result = Faktory::Client::HASHER.(iter, pwd, salt)
    assert_equal "d3590a2722bb8998a6392ed027bcef642b79a58a97219ca4920e9e7f2fe000d7", result
  end

end
