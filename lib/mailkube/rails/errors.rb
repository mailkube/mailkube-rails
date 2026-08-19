# frozen_string_literal: true

module Mailkube
  module Rails
    # Raised when a delivery fails, wrapping the SDK error that caused it.
    #
    # **One class, and deliberately no subclasses.** Re-encoding the SDK's status taxonomy here
    # would mean deciding what an HTTP 429 means, which the contract puts in the SDK's repository.
    # The SDK's own exception is preserved as `cause`, so a caller that wants the category rescues
    # it there, where the categories are defined once.
    #
    # ## Why translate at all
    #
    # Not for silent failure: `Mail::Message#do_delivery` rescues `StandardError` gated on
    # `raise_delivery_errors`, so *any* exception class is already swallowed when an application
    # asks for that. The reason is `deliver_later`. A queued delivery runs inside
    # `ActionMailer::MailDeliveryJob`, and an application's `retry_on` / `discard_on` has to name a
    # class. Naming an SDK class would make that application's retry policy break the day the SDK
    # reorganized its hierarchy; naming this one means the SDK's taxonomy can change without it
    # being a breaking change for consumers.
    #
    # This is the contract's "translate SDK errors into the framework's own error type" clause, in
    # the one form Rails allows: ActionMailer ships no delivery-error class to translate into, so
    # this gem defines the type consumers name.
    #
    #     class OrderMailer < ApplicationMailer
    #       retry_on Mailkube::Rails::DeliveryError, wait: :polynomially_longer
    #     end
    class DeliveryError < StandardError; end
  end
end
