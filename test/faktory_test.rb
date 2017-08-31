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

end
