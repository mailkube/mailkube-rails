# frozen_string_literal: true

module Mailkube
  module Rails
    # The one place this gem turns Rails settings into SDK constructor arguments.
    #
    # Everything that reaches the SDK goes through {build_client}: the delivery method, the webhook
    # endpoint, and anything added later. Two call sites building their own client is how one of
    # them ends up on a different base URL, or without the User-Agent suffix, and the difference
    # shows up as a support question rather than as a failing test.
    #
    # ## Two homes, and no precedence rules
    #
    # Settings live in the two places Rails already puts these kinds of settings, and they do not
    # overlap, so there is nothing to resolve between them:
    #
    # - `config.action_mailer.mailkube_settings` — the delivery credentials. This hash is
    #   what `add_delivery_method` creates, and ActionMailer hands it to the delivery method for
    #   every message, so it is the idiomatic home and needs no invention.
    # - `config.mailkube` — the webhook secret and freshness window, on the
    #   `ActiveSupport::OrderedOptions` the Railtie installs. These are not delivery settings and
    #   putting them under `action_mailer` would misfile them.
    module Config
      # SDK constructor keywords, mapped to the settings key that answers each.
      #
      # One list, so a setting cannot be readable in the delivery method and quietly ignored in
      # a startup check. Adding an SDK keyword is a row here and nothing else.
      CLIENT_KEYS = { api_key: :api_key, base_url: :base_url, timeout: :timeout }.freeze

      # Build an SDK client from a delivery-method settings hash.
      #
      # @param settings [Hash{Symbol => Object}, nil] the `mailkube_settings` hash.
      # @return [Mailkube::Client] the client, carrying this gem's User-Agent suffix.
      # @raise [Mailkube::ConfigurationError] when no API key is available anywhere.
      def self.build_client(settings)
        # Splatted as keywords: a setting this gem did not resolve is simply not passed, which is
        # what leaves the SDK's own default and its environment fallback in charge. Passing an
        # explicit nil would suppress that fallback while looking like configuration.
        Mailkube::Client.new(**client_kwargs(settings), user_agent_suffix: user_agent_suffix)
      end

      # Resolve the SDK keywords that are actually set, dropping the rest.
      #
      # @param settings [Hash{Symbol => Object}, nil] the `mailkube_settings` hash.
      # @return [Hash{Symbol => Object}] the keywords to pass to the SDK.
      def self.client_kwargs(settings)
        given = settings || {}
        kwargs = {} #: Hash[Symbol, untyped]
        CLIENT_KEYS.each do |keyword, key|
          value = given[key]
          # An empty string is treated as unset. It is what an unset `ENV["..."]` interpolated
          # into an initializer produces, and passing it through would defeat the SDK's fallback
          # while looking like a configured value.
          next if value.nil? || value == ""

          kwargs[keyword] = value
        end
        kwargs
      end

      # This gem's own `name/version` token for the SDK's User-Agent.
      #
      # Read from {VERSION} rather than written here. A literal would be a second source of truth
      # that the release process does not update, so it would go stale on the first release and
      # stay wrong for every one after it. The SDK's own token stays leading, so the result is
      # `mailkube/1.1.0 mailkube-rails/0.1.0`.
      #
      # @return [String] the suffix token.
      def self.user_agent_suffix = "mailkube-rails/#{VERSION}"

      # The webhook signing secret, or nil when none is configured.
      #
      # @param app_config [Object] an object responding to `mailkube`, normally `::Rails.application.config`.
      # @return [String, nil] the secret, or nil.
      def self.webhook_secret(app_config)
        value = options(app_config).webhook_secret
        value.is_a?(String) && !value.empty? ? value : nil
      end

      # The signature freshness tolerance, or nil to accept the SDK's documented default.
      #
      # @param app_config [Object] an object responding to `mailkube`.
      # @return [Integer, nil] the window in seconds, or nil.
      def self.webhook_tolerance(app_config)
        value = options(app_config).webhook_tolerance
        value.nil? ? nil : Integer(value)
      end

      # The gem's own options block, tolerating an application that never set one.
      #
      # `ActiveSupport::OrderedOptions` answers nil for any unset key, so this returns an empty one
      # rather than nil and every reader above stays a single expression.
      #
      # @param app_config [Object] an object responding to `mailkube`.
      # @return [ActiveSupport::OrderedOptions] the options block.
      def self.options(app_config)
        app_config.mailkube || ActiveSupport::OrderedOptions.new
      end
    end
  end
end
