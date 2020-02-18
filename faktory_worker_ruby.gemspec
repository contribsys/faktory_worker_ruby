# -*- encoding: utf-8 -*-
require File.expand_path('../lib/faktory/version', __FILE__)

Gem::Specification.new do |gem|
  gem.name          = "faktory_worker_ruby"
  gem.authors       = ["Mike Perham"]
  gem.email         = ["mike@contribsys.com"]
  gem.summary       = "Ruby worker for Faktory"
  gem.description   = "Ruby worker for Faktory."
  gem.homepage      = "https://github.com/contribsys/faktory_worker_ruby"
  gem.license       = "LGPL-3.0"

  gem.executables   = ['faktory-worker']
  gem.files         = `git ls-files | grep -Ev '^(test|myapp|examples)'`.split("\n")
  gem.test_files    = []
  gem.version       = Faktory::VERSION
  gem.required_ruby_version = ">= 2.5.0"

  gem.add_dependency                  'connection_pool', '~> 2.2', ">= 2.2.2"
  gem.add_development_dependency      'activejob', '>= 5.1.5'
  gem.add_development_dependency      'minitest', '~> 5'
  gem.add_development_dependency      'minitest-hooks'
  gem.add_development_dependency      'rake', '~> 12'
end
