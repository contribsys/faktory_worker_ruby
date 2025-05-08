require File.expand_path("../lib/faktory/version", __FILE__)

Gem::Specification.new do |gem|
  gem.name = "faktory_worker_ruby"
  gem.authors = ["Mike Perham"]
  gem.email = ["mike@contribsys.com"]
  gem.summary = "Ruby worker for Faktory"
  gem.description = "Ruby worker for Faktory."
  gem.homepage = "https://github.com/contribsys/faktory_worker_ruby"
  gem.license = "LGPL-3.0"

  gem.executables = ["faktory-worker"]
  gem.files = `git ls-files | grep -Ev '^(test|myapp|examples)'`.split("\n")
  gem.version = Faktory::VERSION
  gem.required_ruby_version = ">= 2.7.0"

  gem.metadata = {
    "homepage_uri" => "https://contribsys.com/faktory",
    "bug_tracker_uri" => "https://github.com/contribsys/faktory_worker_ruby/issues",
    "documentation_uri" => "https://github.com/contribsys/faktory_worker_ruby/wiki",
    "changelog_uri" => "https://github.com/contribsys/faktory_worker_ruby/blob/master/Changes.md",
    "source_code_uri" => "https://github.com/contribsys/faktory_worker_ruby"
  }

  gem.add_dependency "connection_pool", "~> 2.5"
  gem.add_development_dependency "activejob", ">= 7.0.0"
  gem.add_development_dependency "minitest", "~> 5"
  gem.add_development_dependency "minitest-hooks"
  gem.add_development_dependency "rake"
end
