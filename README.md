# mailkube-rails

[![CI](https://github.com/mailkube/mailkube-rails/actions/workflows/ci.yml/badge.svg)](https://github.com/mailkube/mailkube-rails/actions/workflows/ci.yml)
[![Gem](https://img.shields.io/gem/v/mailkube-rails)](https://rubygems.org/gems/mailkube-rails)
[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Code of Conduct](https://img.shields.io/badge/Contributor%20Covenant-2.1-purple.svg)](CODE_OF_CONDUCT.md)

ActionMailer delivery method for mailkube.

Send mail through mailkube using ActionMailer exactly as you already do, and receive webhooks as
`ActiveSupport::Notifications`. This gem is a thin adapter over the
[`mailkube`](https://rubygems.org/gems/mailkube) gem: the API, retries,
errors and signature verification all live there.

Requires Ruby 3.4+ and Rails 7.2.3+.

## Install

```ruby
# Gemfile
gem "mailkube-rails"
```

Then point ActionMailer at it:

```ruby
# config/environments/production.rb
config.action_mailer.delivery_method = :mailkube
config.action_mailer.mailkube_settings = {
  api_key: ENV.fetch("MAILKUBE_API_KEY")
}
```

That is the whole setup. Everything else on this page is optional.

## Sending

Nothing about your application changes. Mailers, `deliver_now`, `deliver_later`, attachments,
`ActionMailer::Base.deliveries` in tests: all of it works as it already did.

```ruby
class OrderMailer < ApplicationMailer
  def shipped(order)
    mail(to: order.customer_email, subject: "Your order shipped")
  end
end

OrderMailer.shipped(order).deliver_later
```

### What is mapped

The sender, recipients (including blind copies), subject, both bodies, attachments and your custom
headers. Anything ActionMailer's message can express, this delivery method passes through.

Send-time features the SDK offers but `Mail::Message` has no slot for — tags, topics, templates,
scheduling, idempotency keys — are reached by using the SDK directly:

```ruby
Mailkube.new.emails.send(
  from: "Acme <hello@yourdomain.com>",
  to: "customer@example.com",
  subject: "Hello world",
  html: "<p>It works!</p>",
  tags: [Mailkube::Tag.new(name: "campaign", value: "spring")]
)
```

> **Inline images degrade to ordinary attachments.** The API's attachment model carries a filename,
> content and content type, with no content id, so a `cid:` reference has nothing to resolve
> against. This is a capability of the platform rather than of this gem.

## Configuration

Two homes, and they do not overlap, so there is nothing to resolve between them.

| Setting | Where | Environment fallback | Default |
|---|---|---|---|
| API key | `config.action_mailer.mailkube_settings[:api_key]` | `MAILKUBE_API_KEY` | required |
| Base URL | `config.action_mailer.mailkube_settings[:base_url]` | `MAILKUBE_BASE_URL` | the SDK's |
| Timeout | `config.action_mailer.mailkube_settings[:timeout]` | | the SDK's |
| Webhook secret | `config.mailkube.webhook_secret` | | required for webhooks |
| Webhook tolerance | `config.mailkube.webhook_tolerance` | | the SDK's |

An unset setting is **omitted** rather than passed along as nil, so the SDK's own environment
resolution still applies. That is why the API key can come from `MAILKUBE_API_KEY`
alone with no Rails configuration at all.

### Two accounts, two mailers

ActionMailer resolves the delivery method per message, so overriding the settings on one mailer
gives it its own client:

```ruby
class MarketingMailer < ApplicationMailer
  self.mailkube_settings = { api_key: ENV.fetch("MARKETING_API_KEY") }
end
```

## Errors

A failed delivery raises `Mailkube::Rails::DeliveryError`, with the SDK's own exception preserved as
`cause`.

```ruby
class OrderMailer < ApplicationMailer
  retry_on Mailkube::Rails::DeliveryError, wait: :polynomially_longer, attempts: 5
end
```

The class this gem owns is what you name, deliberately: naming an SDK class would tie your retry
policy to the SDK's exception hierarchy, and it would break the day that hierarchy was reorganized.
For the detail — which error, which status, whether it is safe to retry — read `cause`, where the
SDK defines the categories once:

```ruby
rescue Mailkube::Rails::DeliveryError => e
  Rails.logger.warn(e.cause.error_name)   # e.g. "quota_exceeded", with status_code and request_id
end
```

`config.action_mailer.raise_delivery_errors = false` still swallows failures exactly as it does for
any other delivery method.

## Webhooks

You write the route. A mountable engine would force a path on your application and drag generator
machinery along for one endpoint, so this gem ships the controller and lets you mount it where you
want:

```ruby
# config/initializers/mailkube.rb
Rails.application.config.mailkube.webhook_secret = ENV.fetch("MAILKUBE_WEBHOOK_SECRET")
```

```ruby
# config/routes.rb
require "mailkube/rails/webhooks_controller"

Rails.application.routes.draw do
  post "/webhooks/mailkube",
       to: Mailkube::Rails::WebhooksController.action(:create)
end
```

The `require` is needed and the `.action(:create)` form is deliberate: a gem's `lib/` is on the load
path but is not an autoload path, so the `"controller#action"` string form would name a constant
Zeitwerk has never been told about.

Deliveries are verified against the **raw** request body and published as one notification:

```ruby
# config/initializers/mailkube.rb
ActiveSupport::Notifications.subscribe("webhook.mailkube") do |*, payload|
  event = payload[:event]

  case event
  when Mailkube::Events::EmailDeliveredEvent then Rails.logger.info("delivered #{event.data.email_id}")
  when Mailkube::Events::EmailBouncedEvent   then Suppression.add(event.data.email_id)
  end
end
```

One notification rather than one per webhook type, so an event this SDK release does not model still
reaches your subscriber with its payload intact instead of being dropped.

Subscribers run **inside the request**, and the endpoint answers as soon as they return. Enqueue
anything slow, or delivery latency becomes retries.

The endpoint answers `204` on success, `400` when verification fails, and `500` when no secret is
configured — the last so that the platform keeps retrying rather than discarding deliveries while
your configuration is broken. CSRF is skipped on this controller because a machine-to-machine POST
cannot present a token; the signature is what authenticates the request, and it is strictly
stronger. Any middleware that decodes and re-encodes the request body breaks verification: it no
longer covers the bytes that were signed.

## Extending this gem

Before adding a setting, a mapped field, or another entry point, read
[`.rules/INTEGRATION_CONTRACT.md`](.rules/INTEGRATION_CONTRACT.md) (what every mailkube framework
integration does identically) and [`.rules/RAILS_INTEGRATION.md`](.rules/RAILS_INTEGRATION.md)
(how those rules land here). Both carry a checklist.

The short version: the capability has to exist in the SDK first, inputs are mapped in `payload.rb`
and never at a call site, and configuration goes through `config.rb`.

This gem ships no `examples/` directory, deliberately: every entry point it exposes needs a host
Rails application before it can run. This README is the wiring documentation, and the spec suite is
what keeps it honest.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development setup and the quality gates every change
must pass. Security issues: see [SECURITY.md](SECURITY.md).

## License

[Apache-2.0](LICENSE) © 2026 Mail Tactic Corporation
