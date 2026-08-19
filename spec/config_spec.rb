# frozen_string_literal: true

# The one config module: Rails settings to SDK keywords, and the User-Agent suffix.
RSpec.describe "configuration" do
  subject(:config) { Mailkube::Rails::Config }

  describe "client keywords" do
    it "passes through the settings that are set" do
      expect(config.client_kwargs(api_key: "mk_test", base_url: "https://example.test/", timeout: 5))
        .to eq(api_key: "mk_test", base_url: "https://example.test/", timeout: 5)
    end

    it "omits an unset setting rather than passing nil" do
      # Load-bearing: the SDK falls back to its own environment variables when an argument is
      # absent, and an explicit nil would suppress that fallback while looking like configuration.
      expect(config.client_kwargs(api_key: "mk_test", base_url: nil)).to eq(api_key: "mk_test")
    end

    it "treats an empty string as unset" do
      # What an unset `ENV["..."]` interpolated into an initializer produces.
      expect(config.client_kwargs(api_key: "mk_test", base_url: "")).to eq(api_key: "mk_test")
    end

    it "tolerates no settings hash at all" do
      expect(config.client_kwargs(nil)).to eq({})
    end
  end

  describe "the User-Agent suffix" do
    it "is this gem's own name and version" do
      expect(config.user_agent_suffix).to eq("mailkube-rails/#{Mailkube::Rails::VERSION}")
    end

    it "reaches the wire, after the SDK's own token" do
      adapter = SpecHelpers::StubAdapter.new
      # The real client, so this asserts what the SDK actually composes rather than what this gem
      # hands it. A literal version here would be a second source of truth that no release updates.
      client = Mailkube::Client.new(
        api_key: "mk_test", http: adapter, user_agent_suffix: config.user_agent_suffix
      )
      client.emails.send(from: "a@x.test", to: "b@y.test", subject: "s")

      agent = adapter.calls.first[:headers]["User-Agent"]

      # Asserted as "the SDK leads, this gem trails", not against a literal SDK token: what that
      # token says is the SDK's business, and pinning it here would make this spec fail on an SDK
      # release that renamed itself, reporting a bug in the wrong repository.
      expect(agent).to match(%r{\A\S+/\S+ })
      expect(agent).to end_with(" #{config.user_agent_suffix}")
    end
  end

  describe "building a client" do
    it "carries the suffix and the resolved settings" do
      client = config.build_client(api_key: "mk_test", base_url: "https://example.test/")

      expect(client).to be_a(Mailkube::Client)
      expect(client.base_url).to eq("https://example.test/")
    end

    it "lets the SDK raise when no key is available anywhere" do
      # This gem does not re-validate configuration the SDK validates; it just does not get in the
      # way of the SDK's own error, which names the environment variable to set.
      expect { config.build_client({}) }.to raise_error(Mailkube::ConfigurationError)
    end
  end

  describe "webhook settings" do
    it "reads the secret and the tolerance" do
      options = app_config(webhook_secret: "whsec_x", webhook_tolerance: 60)

      expect(config.webhook_secret(options)).to eq("whsec_x")
      expect(config.webhook_tolerance(options)).to eq(60)
    end

    it "reports nil for an unset secret, and for an empty one" do
      expect(config.webhook_secret(app_config)).to be_nil
      expect(config.webhook_secret(app_config(webhook_secret: ""))).to be_nil
    end

    it "reports nil for an unset tolerance, so the SDK's default applies" do
      expect(config.webhook_tolerance(app_config)).to be_nil
    end
  end
end
