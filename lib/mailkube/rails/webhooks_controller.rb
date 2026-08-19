# frozen_string_literal: true

require "action_controller"

require_relative "config"

module Mailkube
  module Rails
    # The inbound entry point: verify a delivery, then publish it.
    #
    # This file is **not** required by `lib/mailkube/rails.rb`. It is reached through the route an
    # application writes, so a worker that only sends mail never loads ActionController.
    #
    # ## No engine, deliberately
    #
    # A mountable engine would force a path on every host application and drag `isolate_namespace`
    # plus generator machinery along for one endpoint. Consumers write two lines instead, which
    # also means they choose the path, the constraints and the middleware:
    #
    #     require "mailkube/rails/webhooks_controller"
    #     post "/webhooks/mailkube", to: Mailkube::Rails::WebhooksController.action(:create)
    #
    # The `.action(:create)` form rather than the `"controller#action"` string: a gem's `lib/` is
    # on `$LOAD_PATH` but is not an autoload path, so the string form would resolve to a constant
    # Zeitwerk has never been told about and raise at the first request. The explicit `require` is
    # what makes the constant exist, and is the reason this file can stay off the boot path.
    #
    # This differs from the Laravel integration, where a package registering a route is completely
    # idiomatic and the route is registered for you behind an off-by-default setting.
    #
    # ## It contains no cryptography
    #
    # Verification is the SDK's, in one call. This class adapts Rails' request object to it and
    # publishes the result. See `.rules/INTEGRATION_CONTRACT.md`.
    class WebhooksController < ::ActionController::Base
      # The notification this controller publishes on a verified delivery.
      NOTIFICATION = "webhook.mailkube"

      # A webhook POST is machine-to-machine and cannot carry a CSRF token, so the check is skipped
      # rather than left to reject every delivery. The signature is what authenticates the request,
      # and it is strictly stronger: CSRF protection proves a browser session, while the HMAC
      # proves the sender holds the endpoint secret.
      skip_forgery_protection

      # Receive one webhook delivery.
      #
      # Answers 204 on success, 400 when verification fails, and 500 when no secret is configured.
      #
      # @return [void]
      def create
        secret = Config.webhook_secret(::Rails.application.config)
        # 500, not 4xx. The sender is behaving correctly and the fault is entirely local, so this
        # must read as an outage: the platform then keeps retrying, and the deliveries that arrive
        # while the secret is missing are not silently discarded.
        return head(:internal_server_error) if secret.nil?

        event = Mailkube::Webhooks.verify(
          payload: request.raw_post, headers: header_hash, secret: secret, **tolerance_argument
        )
        ActiveSupport::Notifications.instrument(NOTIFICATION, event: event)
        head :no_content
      rescue Mailkube::SignatureVerificationError, Mailkube::Error
        # A malformed or unverifiable delivery is the sender's problem and a retry cannot fix it,
        # so it is refused rather than retried. The reason is deliberately not reported: an
        # endpoint that distinguishes "bad signature" from "stale timestamp" is an oracle.
        head :bad_request
      end

      private

      # The freshness window, as a splattable hash, or empty to accept the SDK's default.
      #
      # Only the optional argument travels in a splat: the three required ones are named at the
      # call site so Steep checks them against the SDK's own signature. Omitted rather than passed
      # as nil, because nil would be a value the SDK has to interpret rather than an absent one.
      #
      # @return [Hash{Symbol => Integer}] `{tolerance: n}`, or empty.
      def tolerance_argument
        tolerance = Config.webhook_tolerance(::Rails.application.config)
        tolerance.nil? ? {} : { tolerance: tolerance }
      end

      # Convert the Rack environment into the plain Hash the SDK reads headers from.
      #
      # **`request.headers` cannot be passed through**, which is worth stating because it is the
      # obvious thing to write and it fails twice over. `ActionDispatch::Http::Headers` includes
      # `Enumerable` and nothing else, so it has no `transform_keys` and the SDK's normalization
      # raises `NoMethodError` on it. And its `each` delegates to the Rack environment, so
      # converting it to a Hash yields `HTTP_X_WEBHOOK_ID` rather than `X-Webhook-Id` — which
      # downcases to something the SDK's lookup will never match, turning every delivery into a
      # signature failure with no clue as to why.
      #
      # The conversion is generic rather than a list of the three headers the SDK reads today.
      # Naming them would put a copy of the signature scheme's header set in this repository, and
      # the copy would silently stop working the day the scheme grows a fourth.
      #
      # @return [Hash{String => String}] the request headers, in `x-webhook-id` form.
      def header_hash
        headers = {} #: Hash[String, String]
        request.env.each do |name, value|
          next unless name.is_a?(String) && name.start_with?("HTTP_") && value.is_a?(String)

          headers[name.delete_prefix("HTTP_").downcase.tr("_", "-")] = value
        end
        headers
      end
    end
  end
end
