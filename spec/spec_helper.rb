# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  # `skip`, not the older `add_filter`, which SimpleCov 1.x deprecates.
  skip "/spec/"
  # Branch coverage is opt-in: without this line `minimum_coverage branch:` silently gates
  # nothing, which is how a repo ends up believing it has a branch gate that it does not.
  enable_coverage :branch
  minimum_coverage line: 90, branch: 90
end

require "json"
require "mail"
require "action_controller"
require "action_mailer"

require "mailkube/rails"
require "mailkube/rails/webhooks_controller"

# Helpers shared by the whole suite.
#
# ## No host application, and the real SDK
#
# There is no Rails application here, and none is needed: this gem's entry points are a delivery
# method (a plain object `Mail` instantiates) and a controller (which the specs drive directly).
# Booting an application would add minutes to the suite and test Rails rather than this gem.
#
# The **real SDK** runs throughout, over {StubAdapter} passed through `Client.new(http:)`. That is
# the contract's clause, and it is load-bearing: faking the SDK would only prove the specs agree
# with themselves, and would keep passing after the SDK renamed an argument this gem passes by
# name. Every send below therefore exercises the SDK's real config resolution, request building
# and response parsing, and makes zero network calls.
module SpecHelpers
  # An HTTP adapter that records what it was asked to send and replies with a canned response.
  #
  # This is the SDK's own injectable seam, matching `spec/spec_helper.rb` in the SDK repo.
  class StubAdapter
    # @return [Array<Hash>] the requests this adapter received, in order.
    attr_reader :calls

    # @param status [Integer] the status to reply with.
    # @param body [Object] the response body; a Hash is JSON-encoded, a String is sent verbatim.
    def initialize(status: 200, body: { "id" => "abc123" })
      @status = status
      @body = body.is_a?(String) ? body : JSON.generate(body)
      @calls = []
    end

    # @return [Mailkube::HttpResponse] the canned response.
    def call(method:, url:, headers:, body: nil)
      @calls << { method: method, url: url, headers: headers, body: body.nil? ? nil : JSON.parse(body) }
      Mailkube::HttpResponse.new(status: @status, headers: {}, body: @body)
    end

    # @return [Hash, nil] the body of the single request this adapter received.
    def sent = @calls.first&.fetch(:body)
  end

  # A delivery method whose client is wired to a stub adapter.
  #
  # The client is injected rather than built from settings, because what most specs are about is
  # the mapping and the translation, not configuration resolution. `config_spec.rb` covers the
  # construction path, which is the one place it is genuinely under test.
  #
  # @param status [Integer] the status the API should answer with.
  # @param body [Object] the response body.
  # @return [Array(DeliveryMethod, StubAdapter)] the delivery method and its adapter.
  def delivery_with(status: 200, body: { "id" => "abc123" })
    adapter = StubAdapter.new(status: status, body: body)
    delivery = Mailkube::Rails::DeliveryMethod.new({})
    delivery.instance_variable_set(:@client, Mailkube::Client.new(api_key: "mk_test", http: adapter))
    [delivery, adapter]
  end

  # Build a message the way ActionMailer would.
  #
  # @param overrides [Hash] fields to set beyond the minimum.
  # @return [Mail::Message] the message.
  def message(**overrides)
    fields = { from: "hello@acme.test", to: "customer@example.test", subject: "Hello world" }.merge(overrides)
    ::Mail::Message.new do
      fields.each { |name, value| public_send(name, value) }
    end
  end

  # A minimal object standing in for `::Rails.application.config`.
  #
  # An `OrderedOptions` is exactly what the Railtie installs, so this is the real type rather than
  # a double: a double would agree with whatever the spec asserted about it.
  #
  # @param settings [Hash{Symbol => Object}] the gem's own options.
  # @return [Object] an object responding to the gem's config key.
  def app_config(**settings)
    options = ActiveSupport::OrderedOptions.new
    settings.each { |key, value| options[key] = value }
    Struct.new(:mailkube).new(options)
  end
end

RSpec.configure do |config|
  config.include SpecHelpers
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |expectations| expectations.syntax = :expect }
  config.order = :random
  Kernel.srand config.seed
end
