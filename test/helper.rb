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

# ENV["FAKTORY_URL"] = "tcp+tls://test.contribsys.com:7419"
ENV["FAKTORY_URL"] = "tcp://localhost:7419"

require "minitest/hooks/test"
class LiveTest < Minitest::Test
  include Minitest::Hooks
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
