# frozen_string_literal: true

# The structural invariants that Ruby will not enforce and review keeps missing.
RSpec.describe "structure" do
  # Every `.rb` under lib/, read as text. These specs assert about the SOURCE rather than about
  # behaviour, because the failures they catch are ones that only appear inside a booted Rails
  # application — which the contract forbids this suite from having.
  def lib_sources
    root = File.expand_path("../lib", __dir__)
    Dir.glob("#{root}/**/*.rb").to_h { |path| [path.delete_prefix("#{root}/"), File.read(path)] }
  end

  describe "the ::Rails naming trap" do
    it "never names the framework with a bare constant" do
      # Inside `module Mailkube::Rails`, the bare constant `Rails` resolves to THIS gem.
      # `Rails.application` would be a call on this module and `Rails::Railtie` a NameError,
      # and Ruby makes the mistake silently. This is the most likely first bug in any change here,
      # so it is pinned rather than left to review.
      offenders = lib_sources.filter_map do |path, source|
        lines = source.lines.each_with_index.filter_map do |line, index|
          next if line.lstrip.start_with?("#")
          # A `Rails` not preceded by `::`, and not the `module Rails` declaration itself.
          next unless line.match?(/(?<!:)(?<!\w)Rails(::|\.)/)

          "  #{path}:#{index + 1}: #{line.strip}"
        end
        lines.empty? ? nil : lines
      end

      expect(offenders.flatten).to be_empty
    end

    it "shadows the framework constant, which is why the rule exists" do
      # The mechanism, stated directly. Inside `module Mailkube; module Rails` the lexical scope chain is
      # [Mailkube::Rails, Mailkube, Object], and Ruby stops at the first member that owns the
      # name. `Mailkube` owns `Rails`, so a bare `Rails` never reaches Object and never means the
      # framework.
      #
      # Note this cannot be demonstrated with `module_eval("Rails")`: that cref is the single module,
      # `Mailkube` is not in the chain, and lookup falls through to the framework — which would make
      # the trap look imaginary.
      expect(Mailkube.const_defined?(:Rails, false)).to be(true)
      expect(Mailkube.const_get(:Rails, false)).to eq(Mailkube::Rails)
      expect(Mailkube::Rails).not_to eq(::Rails)
    end
  end

  describe "the Railtie" do
    it "registers the delivery method before ActionMailer applies its configuration" do
      # `add_delivery_method` DEFINES the `mailkube_settings` writer, and
      # `action_mailer.set_configs` ends by calling every writer under `config.action_mailer`.
      # Registering after it means an application setting
      # `config.action_mailer.mailkube_settings` gets NoMethodError at boot — which reads as a
      # typo in their configuration rather than as an ordering bug in this gem.
      source = lib_sources.fetch("mailkube/rails/railtie.rb")

      expect(source).to include('before: "action_mailer.set_configs"')
      expect(source).to include("ActiveSupport.on_load(:action_mailer)")
    end

    it "actually registers the delivery method when the hook runs" do
      # The declaration above is text; this runs it. `on_load(:action_mailer)` fires immediately
      # for an already-loaded ActionMailer, so requiring the suite is enough.
      ActiveSupport.on_load(:action_mailer) do
        add_delivery_method :mailkube, Mailkube::Rails::DeliveryMethod
      end

      expect(ActionMailer::Base.delivery_methods[:mailkube]).to eq(Mailkube::Rails::DeliveryMethod)
      expect(ActionMailer::Base).to respond_to(:mailkube_settings)
    end
  end

  describe "the version" do
    it "is the single source the gemspec reads" do
      gemspec = Gem::Specification.load(File.expand_path("../mailkube-rails.gemspec", __dir__))

      expect(gemspec.version.to_s).to eq(Mailkube::Rails::VERSION)
    end

    it "appears as a literal nowhere else" do
      # The version-literal bug appeared in three sibling templates independently.
      offenders = lib_sources.reject { |path, _| path.end_with?("version.rb") }
                             .select { |_, source| source.match?(/"\d+\.\d+\.\d+"/) }

      expect(offenders.keys).to be_empty
    end
  end
end
