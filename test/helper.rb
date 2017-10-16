require 'minitest/pride'
require 'minitest/autorun'

require 'faktory'

module I18n
  def self.locale
    "en"
  end
end

require 'minitest/hooks/test'
class LiveTest < Minitest::Test
  include Minitest::Hooks
end
