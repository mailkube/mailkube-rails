# The Rails realization

Load this alongside `.rules/INTEGRATION_CONTRACT.md` when touching the delivery method, the payload
mapping, the settings surface, the webhook endpoint, or the Railtie.

`INTEGRATION_CONTRACT.md` says what every mailkube framework integration does. This file says how
those rules land in Rails, and records the places this gem deviates.

## What belongs where

| File | Owns |
|---|---|
| `lib/mailkube/rails/railtie.rb` | registration: the delivery method, and the gem's own options block |
| `lib/mailkube/rails/config.rb` | **the one config module**: Rails settings → SDK keywords, and the User-Agent suffix |
| `lib/mailkube/rails/payload.rb` | **the one payload module**: a `Mail::Message` → SDK send keywords |
| `lib/mailkube/rails/delivery_method.rb` | the outbound entry point, and error translation |
| `lib/mailkube/rails/webhooks_controller.rb` | the inbound entry point |
| `lib/mailkube/rails/errors.rb` | the error type consumers name in `retry_on` |

Nothing else may build a client or map a message. If a new entry point needs either, it calls these.

## The naming trap: always write `::Rails`

Inside `module Mailkube::Rails` the bare constant `Rails` resolves to **this gem**, not to the
framework. `Rails::Railtie` is `Mailkube::Rails::Railtie`; `Rails.application` is a call on this
module. Ruby resolves the wrong one **silently**, and the failure surfaces as a `NameError` or
`NoMethodError` a long way from the cause.

So every reference to the framework in this gem is fully qualified as `::Rails`. This is the most
likely first bug in any change here, which is why `spec/naming_spec.rb` pins it rather than trusting
review to catch it.

## The Railtie ordering is load-bearing

`initializer "...", before: "action_mailer.set_configs"` is not tidiness, and reordering it breaks
consumers rather than this gem:

- `add_delivery_method` is what **defines** the `mailkube_settings` class attribute
  (`action_mailer/delivery_methods.rb`: `class_attribute :"#{symbol}_settings"`).
- `action_mailer.set_configs` ends with `options.each { |k, v| send("#{k}=", v) }`, applying
  everything under `config.action_mailer` by calling those writers.

Register after it and an application setting `config.action_mailer.mailkube_settings` gets
`NoMethodError: undefined method 'mailkube_settings='` at boot — which reads as a typo in their
own configuration rather than as an ordering bug here.

The `ActiveSupport.on_load(:action_mailer)` wrapper is separate and also deliberate: naming
`ActionMailer::Base` directly would force it to load at boot for every application, including ones
that never send mail.

## The delivery-method protocol, as `mail` actually invokes it

Read from `mail/message.rb` rather than from the guides, because two details are not documented:

- The class is instantiated **once per message**, with one **positional** settings hash
  (`lookup_delivery_method(method).new(settings)`). It is not a singleton and it is not keyword-based.
- **`settings` must be readable back off the instance.** `Mail::Message#deliver!` evaluates
  `delivery_method.settings[:return_response]`, so a delivery method whose `settings` is nil raises
  there instead of delivering. `attr_reader :settings` is a requirement, not a convention.

There is deliberately **no `open`/`close` lifecycle**. The Django integration has one because
`BaseEmailBackend` defines that protocol; `mail`'s does not, and the SDK client is frozen after
construction with no pool to release. Porting a lifecycle module here would be ceremony modelled on
a protocol Rails does not have.

## Error translation, and why it is not about silent failure

`Mail::Message#do_delivery` already wraps delivery in `rescue => e` gated on
`raise_delivery_errors`, so silent failure works for **any** exception class. That is not the
justification.

The justification is `deliver_later`: a queued delivery runs inside
`ActionMailer::MailDeliveryJob`, and an application's `retry_on` / `discard_on` has to **name a
class**. Naming an SDK class would make that application's retry policy break the day the SDK
reorganized its hierarchy. `DeliveryError` is the class they name instead, so the SDK's taxonomy can
change without it being a breaking change for consumers.

One class, no subclasses: re-encoding the SDK's status taxonomy here would be deciding what an HTTP
429 means, which the contract puts in the SDK's repository. The SDK exception is preserved as
`cause`.

## Two settings homes, and no precedence rules

They do not overlap, so there is nothing to resolve between them:

- `config.action_mailer.mailkube_settings` — the delivery credentials. This is the hash
  `add_delivery_method` creates and ActionMailer hands to the delivery method per message, so it is
  the idiomatic home and needs no invention.
- `config.mailkube` — the webhook secret and freshness window, on the `OrderedOptions` the
  Railtie installs. These are not delivery settings; filing them under `action_mailer` would misplace
  them.

## The payload mapping: `.format` and `.decoded`

Two choices that are silently wrong if shortened:

- **Addresses are rendered with `.format`, not taken bare.** A display name is part of what the
  application asked to send, and dropping it is invisible until somebody reads an inbox.
- **Bodies and attachments come from `.decoded`, never `body.raw_source`.** A quoted-printable body
  read raw ships its transfer encoding to the API verbatim, and the recipient reads `=3D` where an
  equals sign belongs.

Custom headers are every field whose downcased name is not in `RESERVED_HEADERS`. Without that
filter the mapping re-sends `Content-Type: multipart/alternative` as a custom header, describing a
MIME document that is never transmitted.

## Consumers write the webhook route

Unlike the Laravel integration, which registers a route from its service provider, this gem does
not. A mountable engine would force a path on every host application and drag `isolate_namespace`
plus generator machinery along for one endpoint; consumers write two lines and choose the path, the
constraints and the middleware themselves.

`webhooks_controller.rb` is therefore **not required from `lib/mailkube/rails.rb`**. It subclasses
`ActionController::Base`, and a worker process that only sends mail should not be made to load
ActionController. That is also why `actionpack` is not a gemspec dependency: every Rails application
that can route a request already has it.

Three details in that controller are each a bug if changed:

1. **`request.raw_post`, not `request.body.read`.** `raw_post` caches into `RAW_POST_DATA` and stays
   readable; `body.read` leaves the IO at EOF, so a later `params` access sees an empty body.
2. **The header hash is built from the Rack environment, generically.** `request.headers` cannot be
   passed to the SDK: `ActionDispatch::Http::Headers` includes only `Enumerable`, so it has no
   `transform_keys` and the SDK's normalization raises `NoMethodError` on it — and its `each`
   delegates to the Rack environment, so converting it yields `HTTP_X_WEBHOOK_ID`, which downcases
   to something the SDK's lookup never matches. Naming the three headers explicitly would be a copy
   of the signature scheme's header set living here, so the conversion is generic instead.
3. **A missing secret answers 500, not 4xx.** The sender is behaving correctly and the fault is
   entirely local, so it must read as an outage and the platform must keep retrying. A 4xx would
   make the platform discard deliveries that arrive while the secret is unset.

## `ActiveSupport::Notifications`, not a bespoke callback

It is the only notification bus Rails ships, it is what `ActiveSupport::Notifications.subscribe`
already listens to, and it is the structural twin of the Django integration's `Signal`. One
notification name carrying the SDK's typed event, never one per event type: a notification per type
would duplicate the SDK's catalogue in a second place that has to be extended on every platform
release, and a receiver deployed before that release would silently stop seeing the new type.

## Deviations from the shared contract

Both are deliberate, and both are the kind of thing that gets "fixed" by someone who has not read
this file.

1. **`sig/vendor/` exists and is not shipped.** There are no maintained RBS signatures for Rails,
   ActionMailer or `mail`, so this gem hand-writes the slice it calls. They are excluded from
   `spec.files`: publishing partial Rails signatures would put them on the load path of anyone who
   types this gem, competing with whatever real signatures they use. What `steep` therefore checks
   is this gem's calls **into the SDK**, which is fully typed — the boundary that breaks silently
   when the SDK moves.
2. **No `examples/` directory.** Every entry point here needs a host Rails application before it can
   run, so a runnable script would need one scaffolded first, and would rot the moment it drifted.
   The wiring lives in `README.md` and the specs are what keep it honest. `ci.yml` says so where the
   example-compilation job would have been, rather than leaving a silent gap.

## Tests

No host application and no database, because this gem persists nothing and its entry points are a
plain object and a controller the specs drive directly. Never reach for a Rails app in a spec; if a
change appears to need one, that change is arguing with the contract.

The **real SDK** runs throughout, over a stub HTTP adapter passed through `Client.new(http:)`.
Faking the SDK would only prove the specs agree with themselves, and would keep passing after the
SDK renamed an argument this gem passes by name.

Webhook fixtures are signed with the SDK's own `Webhooks.sign`, never with an HMAC written in the
spec. A fixture built from a second implementation only proves the spec agrees with itself, and
would keep passing if the SDK changed the scheme.
