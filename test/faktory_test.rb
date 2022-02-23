require "helper"
require "stringio"

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
    result = Faktory::Client::HASHER.call(iter, pwd, salt)
    assert_equal "6d877f8e5544b1f2598768f817413ab8a357afffa924dedae99eb91472d4ec30", result
  end
end
