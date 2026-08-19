# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)
RuboCop::RakeTask.new

desc "Validate the RBS signatures are internally coherent"
task :rbs do
  # `-r mailkube` first: the SDK ships its own signatures inside the gem, and this gem's
  # `sig/` names its types. Without it every reference to an SDK type is "Could not find". Keep this
  # list in step with the `library` calls in the Steepfile and with the same step in ci.yml.
  sh "rbs -r mailkube -r uri -r time -r openssl -r json -r net-http -r socket -I sig validate"
end

desc "Check the implementation against the RBS signatures"
task :steep do
  sh "steep check"
end

desc "Run every gate this repo's CI runs"
task default: %i[rubocop rbs steep spec]
