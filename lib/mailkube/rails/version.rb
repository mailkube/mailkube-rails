# frozen_string_literal: true

module Mailkube
  module Rails
    # This gem's version, and the only place it is written.
    #
    # The gemspec reads it, and so does the User-Agent suffix, so a release cannot report one
    # version to RubyGems and a different one to the API. It stays at 0.0.0 in the repository:
    # semantic-release rewrites this line in the release runner and never commits it back. See
    # `.rules/RELEASE.md`.
    VERSION = "0.0.0"
  end
end
