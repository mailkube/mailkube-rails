# frozen_string_literal: true

# The outbound entry point: the delivery-method protocol, and error translation.
RSpec.describe "delivery" do
  it "sends the mapped payload through the SDK" do
    delivery, adapter = delivery_with
    delivery.deliver!(message(body: "plain"))

    expect(adapter.calls.length).to eq(1)
    expect(adapter.sent).to include("from" => "hello@acme.test", "to" => ["customer@example.test"],
                                    "subject" => "Hello world", "text" => "plain")
  end

  it "returns the SDK's result" do
    delivery, = delivery_with(body: { "id" => "email_123", "message_id" => "<abc@mailkube>" })
    result = delivery.deliver!(message)

    expect(result).to be_a(Mailkube::Email)
    expect(result.id).to eq("email_123")
  end

  it "exposes the settings it was built with" do
    # Not a convention: `Mail::Message#deliver!` evaluates `delivery_method.settings[:return_response]`,
    # so a delivery method whose `settings` is nil raises there instead of delivering.
    expect(Mailkube::Rails::DeliveryMethod.new(api_key: "mk_test").settings).to eq(api_key: "mk_test")
  end

  it "tolerates being built with no settings at all" do
    # `Mail` passes `{}` by default and ActionMailer can pass nil, and `settings[...]` must still work.
    expect(Mailkube::Rails::DeliveryMethod.new(nil).settings).to eq({})
  end

  it "does not build a client until something is actually delivered" do
    # ActionMailer instantiates a delivery method while wrapping a message even when the message is
    # never sent — test-mailer substitution, `deliver_later` handing off to a job, an interceptor
    # that aborts. A missing API key must not raise on any of those paths.
    expect { Mailkube::Rails::DeliveryMethod.new({}) }.not_to raise_error
  end

  describe "error translation" do
    it "raises DeliveryError, keeping the SDK error as the cause" do
      delivery, = delivery_with(status: 429, body: { "name" => "rate_limit_exceeded" })

      # The consequence this pins: `retry_on` names a class, and it has to be one this gem owns, or
      # every consumer's retry policy breaks when the SDK reorganizes its hierarchy.
      expect { delivery.deliver!(message) }.to raise_error(Mailkube::Rails::DeliveryError) do |error|
        expect(error.cause).to be_a(Mailkube::RateLimitError)
        expect(error.cause.status_code).to eq(429)
      end
    end

    it "translates a transport failure too, not only an API error" do
      delivery = Mailkube::Rails::DeliveryMethod.new({})
      raising = Class.new do
        def call(**) = raise Mailkube::ConnectionError, "connection refused"
      end.new
      delivery.instance_variable_set(:@client, Mailkube::Client.new(api_key: "mk_test", http: raising))

      expect { delivery.deliver!(message) }.to raise_error(Mailkube::Rails::DeliveryError)
    end

    it "is one class with no subclasses" do
      # Re-encoding the SDK's status taxonomy here would be deciding what a 429 means, which the
      # contract puts in the SDK's repository.
      subclasses = ObjectSpace.each_object(Class).select { |klass| klass < Mailkube::Rails::DeliveryError }
      expect(subclasses).to be_empty
    end
  end
end
