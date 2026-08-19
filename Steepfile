# frozen_string_literal: true

# Steep is the half of the type gate that actually reads `lib/`.
#
# `rbs validate` proves the signatures are internally coherent and nothing more: it never loads
# the implementation, so a `sig/` describing methods that do not exist passes it. Steep compares
# the two. Both run in CI; neither is sufficient alone.
target :lib do
  # `sig/vendor/` carries the hand-written slice of Rails this gem calls. It is on the signature
  # path here and excluded from `spec.files` in the gemspec, so it types the build without being
  # published into anybody else's load path.
  signature "sig"
  check "lib"

  # The SDK ships its own `sig/` inside the gem, and RBS loads a gem's bundled signatures by name.
  # That is the point of the type gate here: this gem's calls into the SDK are checked against the
  # SDK's own declarations, so a renamed keyword is a red build rather than a runtime TypeError in
  # somebody's production mailer.
  library "mailkube"

  # The stdlib this gem uses, directly or through the SDK's signatures. RBS only loads the ones a
  # target names, so an unnamed one surfaces as "cannot find the declaration of constant" rather
  # than as a missing dependency. Keep this in step with the `-r` flags on the `rbs validate`
  # command in the Rakefile and in ci.yml.
  library "uri", "time", "openssl", "json", "net-http", "socket"

  configure_code_diagnostics do |hash|
    # A method in `lib/` that no signature declares is the drift this gate exists to catch. It is
    # a warning by default, which `steep check` exits 0 on, so it is promoted here.
    hash[Steep::Diagnostic::Ruby::UndeclaredMethodDefinition] = :error
  end
end
