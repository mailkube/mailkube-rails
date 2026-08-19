# frozen_string_literal: true

require "rails/railtie"

module Mailkube
  module Rails
    # Registers the delivery method, and the gem's own options block, at boot.
    #
    # Note `::Rails::Railtie`, fully qualified. Inside this namespace the bare constant
    # `Rails` is Mailkube::Rails, so `Rails::Railtie` would be a NameError at load. Every
    # reference to the framework in this gem is written this way.
    class Railtie < ::Rails::Railtie
      # The gem's own settings block, so `config.mailkube.webhook_secret = ...` works in an
      # initializer. `OrderedOptions` answers nil for anything unset, which is what lets
      # {Config} read a key an application never assigned.
      config.mailkube = ActiveSupport::OrderedOptions.new

      # `before: "action_mailer.set_configs"` is load-bearing, not tidiness.
      #
      # `add_delivery_method` is what DEFINES the `mailkube_settings` class attribute
      # (`action_mailer/delivery_methods.rb`: `class_attribute :"#{symbol}_settings"`). Rails then
      # applies everything under `config.action_mailer` by calling those writers, with a bare
      # `options.each { |k, v| send("#{k}=", v) }` at the end of `action_mailer.set_configs`.
      #
      # Register after that and an application setting `config.action_mailer.mailkube_settings`
      # gets `NoMethodError: undefined method 'mailkube_settings='` at boot, which reads as a
      # typo in their own config rather than as an ordering bug in this gem. `spec/naming_spec.rb`
      # pins the declaration.
      #
      # The `on_load` hook is what defers the work until ActionMailer is actually loaded: naming
      # the constant directly here would force it, and an application that does not use
      # ActionMailer would pay for it at every boot.
      initializer "mailkube-rails.add_delivery_method", before: "action_mailer.set_configs" do
        ActiveSupport.on_load(:action_mailer) do
          # steep:ignore:start
          # `self` inside this block is `ActionMailer::Base`, which the framework substitutes at
          # load time. No signature can express that, and modelling ActionMailer::Base in
          # sig/vendor/ purely to satisfy one call would be a large stub for no checking value.
          add_delivery_method :mailkube, Mailkube::Rails::DeliveryMethod
          # steep:ignore:end
        end
      end
    end
  end
end
