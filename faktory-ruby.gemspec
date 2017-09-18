# -*- encoding: utf-8 -*-
require File.expand_path('../lib/faktory/version', __FILE__)

Gem::Specification.new do |gem|
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mike@contribsys.com"]
  gem.summary       = "Ruby worker for Faktory"
  gem.description   = "Ruby worker for Faktory."
  gem.homepage      = "http://contribsys.com"
  gem.license       = "LGPL-3.0"

  gem.executables   = ['faktory-worker']
  gem.files         = `git ls-files | grep -Ev '^(test|myapp|examples)'`.split("\n")
  gem.test_files    = []
  gem.name          = "faktory-ruby"
  gem.require_paths = ["lib"]
  gem.version       = Faktory::VERSION
  gem.required_ruby_version = ">= 2.2.2"

  gem.add_dependency                  'connection_pool', '~> 2.2', ">= 2.2.1"
  gem.add_development_dependency      'minitest', '~> 5'
  gem.add_development_dependency      'rake', '~> 12'
end
