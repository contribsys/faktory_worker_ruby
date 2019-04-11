$TESTING = true
require 'minitest/pride'
require 'minitest/autorun'

require 'faktory'
require 'faktory/testing'

module I18n
  def self.locale
    "en"
  end
end

require 'minitest/hooks/test'
class LiveTest < Minitest::Test
  include Minitest::Hooks
end

def pro_only
  (@desc ||= Faktory.server_pool.with do |c|
    data = c.info
    data["server"]["description"]
  end).index("Pro")
end
