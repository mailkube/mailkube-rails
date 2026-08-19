# frozen_string_literal: true

require_relative "lib/mailkube/rails/version"

Gem::Specification.new do |spec|
  spec.name = "mailkube-rails"
  # The version has exactly one source of truth and this reads it. Never write a literal here:
  # a second copy is how a gem ends up reporting a version it is not, and this gem's version is
  # also what it puts in the User-Agent.
  spec.version = Mailkube::Rails::VERSION
  spec.authors = ["Mailtactic, Corp."]
  spec.summary = "ActionMailer delivery method for mailkube."
  # Distinct from the summary on purpose: `gem build` warns when the two are identical, and
  # RubyGems renders them in different places.
  spec.description = "ActionMailer delivery method for mailkube. A thin adapter over the mailkube gem: " \
                     "deliver through ActionMailer, receive webhooks as ActiveSupport notifications."
  spec.homepage = "https://github.com/mailkube/mailkube-rails"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.4"

  # `homepage_uri` is deliberately absent: `spec.homepage` already supplies it, and repeating the
  # same URL under two metadata keys makes `gem build` warn that only one will be shown.
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    # The GitHub Releases page IS the changelog: releases commit nothing back to `main`, so
    # there is no CHANGELOG.md to link. See .rules/RELEASE.md.
    "changelog_uri" => "#{spec.homepage}/releases",
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "documentation_uri" => "https://rubydoc.info/gems/mailkube-rails",
    "rubygems_mfa_required" => "true"
  }

  # Ship the library, its signatures and the licence, and nothing else. `git ls-files` is
  # deliberately not used: it makes the built gem depend on the checkout being a git working
  # tree, which is false in a release runner that downloads a tarball.
  #
  # `sig/vendor/` is excluded on purpose. Those are hand-written stubs for the SLICE of Rails this
  # gem calls, written to satisfy `steep check` here; shipping them would put a second, partial
  # set of Rails signatures on the load path of anyone who types this gem, and RBS has no way to
  # tell that theirs should win.
  spec.files = Dir["lib/**/*.rb", "sig/**/*.rbs", "LICENSE", "NOTICE", "README.md"].reject do |path|
    path.start_with?("sig/vendor/")
  end
  spec.require_paths = ["lib"]

  # Unlike the SDK, this gem HAS runtime dependencies, and each one is here for a reason:
  #
  #   mailkube     the SDK. Every byte on the wire is its business, not this gem's.
  #   railties     the Railtie that registers the delivery method at boot.
  #   actionmailer the delivery-method protocol, and `add_delivery_method` itself.
  #
  # `actionpack` is deliberately NOT a dependency even though the webhook controller subclasses
  # `ActionController::Base`: that file is never required by `lib/mailkube/rails.rb`, so a
  # non-web application (a worker that only sends) never loads it. Every Rails app that can route
  # a request already has actionpack, and a `--api` app that does not want the controller should
  # not be made to install it.
  #
  # The upper bound is the next major, not the next minor: Rails is disciplined about semver for
  # the framework-facing hooks this gem uses, and a `~>` on the minor would open a dependency PR
  # every six weeks for a constraint nothing had tested against.
  #
  # The lower bound carries a full patch version because a floor has to name a release that can
  # actually be installed. Two things make that stricter than it looks, and the `floor` job is what
  # found both: `= 7.2` matches no published gem, and Rails 7.2.0 to 7.2.2 are permanently
  # uninstallable — `actionpack < 7.2.3` pins `rack < 3.2` while every published `rack-session`
  # now requires `rack >= 3.2`. A floor nobody can resolve is a promise this gem cannot keep.
  spec.add_dependency "actionmailer", ">= 7.2.3", "< 9"
  spec.add_dependency "mailkube", ">= 1.1.0", "< 2"
  spec.add_dependency "railties", ">= 7.2.3", "< 9"
end
