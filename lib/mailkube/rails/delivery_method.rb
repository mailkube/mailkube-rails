# frozen_string_literal: true

module Mailkube
  module Rails
    # The ActionMailer delivery method: the outbound entry point, and error translation.
    #
    # ## The protocol this implements
    #
    # `Mail` instantiates a delivery method **once per message**, with one positional settings
    # hash (`mail/message.rb`: `lookup_delivery_method(method).new(settings)`), then calls
    # `deliver!(mail)`. Two consequences shape this class:
    #
    # - `settings` must be readable back off the instance. `Mail::Message#deliver!` evaluates
    #   `delivery_method.settings[:return_response]`, so a delivery method whose `settings` is nil
    #   raises there rather than delivering. It is a real requirement, not a convention.
    # - The instance is per-message and short-lived, so the SDK client is memoized on it and that
    #   is the whole lifecycle. There is deliberately no open/close pair: the SDK client is frozen
    #   after construction and holds no pool to release, so a lifecycle module here would be
    #   ceremony modelled on a protocol Rails does not have.
    class DeliveryMethod
      # @return [Hash{Symbol => Object}] the settings ActionMailer built this instance with.
      attr_reader :settings

      # @param settings [Hash{Symbol => Object}, nil] the `mailkube_settings` hash.
      def initialize(settings = {})
        @settings = settings || {}
      end

      # Deliver one message.
      #
      # @param message [Mail::Message] the message to send.
      # @return [Mailkube::Email] the SDK's accepted-send result.
      # @raise [DeliveryError] when the SDK reports any failure.
      def deliver!(message)
        fields = Payload.build(message)
        # The three required keywords are named rather than left inside the splat. Steep cannot
        # prove a Hash carries them, so a bare `**fields` would report them missing — and silencing
        # that would silence the one check worth having here, which is that this gem still calls
        # the SDK the way the SDK declares. A renamed keyword has to be a red build, not a
        # production TypeError inside somebody's mailer.
        client.emails.send(from: fields[:from], to: fields[:to], subject: fields[:subject],
                           **fields.except(:from, :to, :subject))
      rescue Mailkube::Error => e
        # Translated at the boundary, with the SDK error kept as `cause` so nothing is lost. See
        # DeliveryError for why this matters even though `do_delivery` already rescues broadly.
        raise DeliveryError, e.message
      end

      # The SDK client for this delivery, built once.
      #
      # Lazy rather than built in the constructor: ActionMailer instantiates a delivery method
      # while wrapping a message even when the message is never delivered — `Mail::TestMailer`
      # substitution, `deliver_later` handing off to a job, an interceptor that aborts — and a
      # missing API key must not raise on any of those paths.
      #
      # @return [Mailkube::Client] the client.
      def client = @client ||= Config.build_client(@settings)
    end
  end
end
