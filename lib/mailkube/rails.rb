# frozen_string_literal: true

require "mailkube"

require_relative "rails/version"
require_relative "rails/errors"
require_relative "rails/config"
require_relative "rails/payload"
require_relative "rails/delivery_method"
require_relative "rails/railtie"

module Mailkube
  # ActionMailer delivery for mailkube, and an inbound webhook endpoint.
  #
  # This module is a **thin adapter**. The wire format, authentication, retry policy, error
  # taxonomy and webhook signature scheme all belong to the `mailkube` gem; nothing here
  # re-implements any of them. See `.rules/INTEGRATION_CONTRACT.md`.
  #
  # Requiring this file loads the delivery half only. {WebhooksController} is deliberately NOT
  # required here: it subclasses `ActionController::Base`, and a worker process that only sends
  # mail should not be made to load ActionController. Applications that receive webhooks reach it
  # through the route they write, which autoloads it.
  #
  # ## The naming trap
  #
  # Inside this namespace the bare constant `Rails` resolves to **this module**, not to the
  # framework. Every reference to the framework is therefore written `::Rails`, fully
  # qualified. Ruby resolves the wrong one silently and the result is a `NoMethodError` a long way
  # from the cause, so this is the most likely first bug in any change here. `spec/naming_spec.rb`
  # pins it.
  module Rails
  end
end
