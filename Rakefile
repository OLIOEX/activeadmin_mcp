# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run the end-to-end suite against a generated ActiveAdmin application"
RSpec::Core::RakeTask.new(:e2e) do |t|
  t.pattern = "spec/e2e/**/*_spec.rb"
  t.rspec_opts = "--require ./spec/e2e/e2e_helper.rb --format documentation --exclude-pattern ''"
end

task default: :spec
