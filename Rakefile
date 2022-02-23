require "bundler/gem_tasks"
require "rake/testtask"
require "standard/rake"

Rake::TestTask.new(:test) do |test|
  test.libs += ["test"]
  test.warning = true
  test.pattern = "test/**/*_test.rb"
end

task default: ["standard:fix", :test]
