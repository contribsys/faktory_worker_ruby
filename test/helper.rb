$TESTING = true
require "simplecov"
SimpleCov.start

require "minitest/pride"
require "minitest/autorun"

require "faktory"
require "faktory/testing"

module I18n
  def self.locale
    "en"
  end
end

require "minitest/hooks/test"
class LiveTest < Minitest::Test
  include Minitest::Hooks
end

def pro?
  @desc ||= Faktory.server_pool.with do |c|
    data = c.info
    data["server"]["description"]
  end
  @desc.index("Pro") || @desc.index("Enterprise")
end

def pro_only
  yield if pro?
end

def ent_only
  yield if ent?
end

def ent?
  (@desc ||= Faktory.server_pool.with do |c|
    data = c.info
    data["server"]["description"]
  end).index("Enterprise")
end
