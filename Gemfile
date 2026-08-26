# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# ── The two matrix axes, both driven from here ────────────────────────────────
# An integration is the one package that can be broken by something it does not depend on
# directly: the host framework's next major. So Rails is a matrix axis of its own, separate from
# Ruby, and both axes are switched by an environment variable rather than by a second gemfile.
#
# Appraisal would be the usual answer and is deliberately not used: it is another dependency, and
# it generates gemfiles that have to be regenerated and committed whenever the constraints move.
# `Gemfile.lock` is gitignored here (a library must resolve fresh, see .gitignore), so those files
# would be checked-in state describing a resolution nothing reads.

# An empty value counts as unset, which is not pedantry: a CI matrix leg that omits the variable
# still exports it as "", and Ruby's `""` is truthy. Without this, `RAILS_VERSION=""` renders the
# constraint `~> .0` and Bundler aborts with "Illformed requirement" before any gate runs.
switch = ->(name) { (value = ENV.fetch(name, nil)) && !value.empty? ? value : nil }

# RAILS_VERSION pins the framework axis. Unset means "whatever the gemspec allows", which is what
# a developer wants locally and what the newest supported leg tests.
if (rails_version = switch.call("RAILS_VERSION"))
  %w[actionmailer actionpack railties].each do |name|
    gem name, "~> #{rails_version}.0"
  end
end

# DEPENDENCY_FLOOR resolves every runtime dependency DOWN to the oldest version the gemspec
# allows. Bundler has no `--prefer-lowest`, so the floors are pinned explicitly — but they are
# READ FROM THE GEMSPEC, which is the one place this gem declares them. Writing them again here
# would create a second copy that goes stale silently, and the stale one is the copy CI believes.
if switch.call("DEPENDENCY_FLOOR")
  spec = Gem::Specification.load(File.expand_path("mailkube-rails.gemspec", __dir__))
  spec.dependencies.select { |dependency| dependency.type == :runtime }.each do |dependency|
    floor = dependency.requirement.requirements.find { |operator, _| [">=", "~>"].include?(operator) }&.last
    gem dependency.name, "= #{floor}" if floor
  end
end

# Development tooling is pinned EXACTLY, not pessimistically.
#
# Every gem below can turn a green repo red without a line of this repo changing: RuboCop enables
# new cops in a minor, Steep tightens inference in a minor, and both run as CI gates. Bump them
# deliberately, in their own PR, with the failures fixed in the same change.
group :development do
  gem "rake", "13.4.2"
  gem "rbs", "4.1.3"
  gem "rubocop", "1.89.0"
  gem "rubocop-rspec", "3.10.2"
  gem "steep", "2.0.0"
end

group :test do
  gem "rspec", "3.13.2"
  gem "simplecov", "1.1.1"
end
