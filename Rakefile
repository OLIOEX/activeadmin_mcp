# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

desc "Run the end-to-end suite against a generated ActiveAdmin application"
RSpec::Core::RakeTask.new(:e2e) do |t|
  t.pattern = "spec/e2e/**/*_spec.rb"
  # --options replaces the project .rspec wholesale rather than merging with
  # it, so the project's --require spec_helper and --exclude-pattern never
  # apply here: this suite loads only spec/e2e/e2e_helper.rb.
  t.rspec_opts = "--options spec/e2e/e2e.opts"
end

task default: :spec
