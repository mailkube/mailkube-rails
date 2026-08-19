# frozen_string_literal: true

require "rack"

# The inbound entry point: verification against the raw bytes, and publication.
RSpec.describe "webhooks" do
  let(:secret) { "whsec_test" }
  let(:body) { JSON.generate({ "type" => "email.delivered", "data" => { "email_id" => "email_123" } }) }
  let(:timestamp) { Time.now.utc.iso8601 }

  # Signed with the SDK's own signer, never with an HMAC written here. A fixture built from a
  # second implementation only proves this spec agrees with itself, and would keep passing if the
  # SDK changed the scheme.
  def signed_headers(id: "evt_1", payload: body, key: secret)
    {
      "HTTP_X_WEBHOOK_ID" => id,
      "HTTP_X_WEBHOOK_TS" => timestamp,
      "HTTP_X_WEBHOOK_SIG" => Mailkube::Webhooks.sign(id: id, timestamp: timestamp, payload: payload, secret: key)
    }
  end

  # Drive the controller as the Rack application it is, so no host Rails application is needed.
  def post_webhook(payload: body, headers: signed_headers, config: app_config(webhook_secret: secret))
    allow(::Rails).to receive(:application).and_return(Struct.new(:config).new(config))
    env = ::Rack::MockRequest.env_for("/webhooks/mailkube", method: "POST", input: payload)
    Mailkube::Rails::WebhooksController.action(:create).call(env.merge(headers))
  end

  it "accepts a correctly signed delivery" do
    status, = post_webhook

    expect(status).to eq(204)
  end

  it "publishes the typed event as one notification" do
    received = []
    subscription = ActiveSupport::Notifications.subscribe("webhook.mailkube") do |*, payload|
      received << payload[:event]
    end

    post_webhook
    ActiveSupport::Notifications.unsubscribe(subscription)

    expect(received.length).to eq(1)
    expect(received.first).to be_a(Mailkube::Events::EmailDeliveredEvent)
    expect(received.first.data.email_id).to eq("email_123")
  end

  it "publishes an event type this SDK release does not model, rather than dropping it" do
    unknown = JSON.generate({ "type" => "email.teleported", "data" => {} })
    received = []
    subscription = ActiveSupport::Notifications.subscribe("webhook.mailkube") { |*, p| received << p[:event] }

    post_webhook(payload: unknown, headers: signed_headers(payload: unknown))
    ActiveSupport::Notifications.unsubscribe(subscription)

    # One notification carrying the SDK's typed event, never one per type: a subscriber deployed
    # before a platform release must not silently stop seeing new events.
    expect(received.first).to be_a(Mailkube::Events::UnknownEvent)
    expect(received.first["type"]).to eq("email.teleported")
  end

  it "refuses a delivery signed with the wrong secret" do
    status, = post_webhook(headers: signed_headers(key: "whsec_wrong"))

    expect(status).to eq(400)
  end

  it "refuses a delivery whose body was altered after signing" do
    # The point of verifying the RAW bytes. Signing one payload and sending another is exactly what
    # re-encoding the body does, and it is why `request.raw_post` is used rather than `params`.
    status, = post_webhook(payload: JSON.generate({ "type" => "email.bounced" }))

    expect(status).to eq(400)
  end

  it "refuses a delivery with no signature headers at all" do
    status, = post_webhook(headers: {})

    expect(status).to eq(400)
  end

  it "answers 500, not 4xx, when no secret is configured" do
    # The sender is behaving correctly and the fault is entirely local, so this has to read as an
    # outage: the platform keeps retrying, and deliveries arriving meanwhile are not discarded.
    status, = post_webhook(config: app_config)

    expect(status).to eq(500)
  end

  it "honours a configured freshness tolerance" do
    stale = (Time.now.utc - 600).iso8601
    headers = {
      "HTTP_X_WEBHOOK_ID" => "evt_1",
      "HTTP_X_WEBHOOK_TS" => stale,
      "HTTP_X_WEBHOOK_SIG" => Mailkube::Webhooks.sign(id: "evt_1", timestamp: stale, payload: body, secret: secret)
    }

    fresh = post_webhook(headers: headers, config: app_config(webhook_secret: secret, webhook_tolerance: 3600))
    strict = post_webhook(headers: headers, config: app_config(webhook_secret: secret, webhook_tolerance: 60))

    expect(fresh.first).to eq(204)
    expect(strict.first).to eq(400)
  end

  it "is not loaded by requiring the gem" do
    # The controller subclasses ActionController::Base, and a worker that only sends mail must not
    # be made to load ActionController. The spec suite requires it explicitly; `lib/mailkube/rails.rb`
    # must not.
    entrypoint = File.read(File.expand_path("../lib/mailkube/rails.rb", __dir__))

    expect(entrypoint).not_to include("webhooks_controller")
  end
end
