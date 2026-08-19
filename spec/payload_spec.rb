# frozen_string_literal: true

# The payload module's contract: which part of a message answers which SDK argument.
RSpec.describe "payload mapping" do
  subject(:payload) { Mailkube::Rails::Payload }

  it "maps the ordinary fields" do
    mapped = payload.build(message(body: "plain"))

    expect(mapped[:from]).to eq("hello@acme.test")
    expect(mapped[:to]).to eq(["customer@example.test"])
    expect(mapped[:subject]).to eq("Hello world")
    expect(mapped[:text]).to eq("plain")
  end

  it "keeps display names on recipients" do
    mapped = payload.build(message(to: "A Customer <customer@example.test>"))

    # `.format` rather than the bare address: a recipient's display name is part of what the
    # application asked to send, and dropping it is invisible until someone reads an inbox.
    expect(mapped[:to]).to eq(["A Customer <customer@example.test>"])
  end

  it "maps every recipient field" do
    mapped = payload.build(message(cc: "cc@example.test", bcc: "bcc@example.test", reply_to: "reply@acme.test"))

    expect(mapped[:cc]).to eq(["cc@example.test"])
    expect(mapped[:bcc]).to eq(["bcc@example.test"])
    expect(mapped[:reply_to]).to eq(["reply@acme.test"])
  end

  it "never publishes a blind copy as a visible recipient" do
    mapped = payload.build(message(bcc: "secret@example.test"))

    # The failure this pins is a disclosure, not a crash: taking recipients from a single merged
    # list puts every blind copy in `to`, and every recipient then sees the whole list.
    expect(mapped[:to]).to eq(["customer@example.test"])
    expect(mapped[:to]).not_to include("secret@example.test")
  end

  it "decodes a quoted-printable body rather than shipping its transfer encoding" do
    mail = message
    mail.body = "café costs 5 € — always"
    mail.content_transfer_encoding = "quoted-printable"

    # `.decoded`, never `body.raw_source`: read raw, this body arrives as `caf=C3=A9` and the
    # recipient reads the escapes instead of the text.
    expect(payload.build(mail)[:text]).to eq("café costs 5 € — always")
  end

  it "maps both bodies of a multipart message" do
    mail = message
    mail.text_part = ::Mail::Part.new { body "plain" }
    mail.html_part = ::Mail::Part.new do
      content_type "text/html; charset=UTF-8"
      body "<p>rich</p>"
    end

    mapped = payload.build(mail)

    expect(mapped[:text]).to eq("plain")
    expect(mapped[:html]).to eq("<p>rich</p>")
  end

  it "converts attachments as decoded bytes" do
    mail = message
    mail.attachments["notes.txt"] = { mime_type: "text/plain", content: "raw bytes" }

    attachment = payload.build(mail)[:attachments].first

    expect(attachment).to be_a(Mailkube::Attachment)
    expect(attachment.filename).to eq("notes.txt")
    expect(attachment.content_type).to eq("text/plain")
    # The SDK base64-encodes for the wire. Encoding here too would send them twice over.
    expect(attachment.content).to eq("raw bytes")
  end

  it "forwards custom headers and drops the derived ones" do
    mail = message
    mail.header["X-Campaign"] = "spring"

    headers = payload.build(mail)[:headers]

    expect(headers).to include("X-Campaign" => "spring")
    # `content-type` describes a MIME document that is never transmitted: this gem hands over
    # structured fields instead, so re-sending it would contradict what the API builds.
    expect(headers.keys.map(&:downcase)).not_to include("content-type", "subject", "from", "to")
  end

  it "omits absent fields entirely" do
    mapped = payload.build(message(body: "plain"))

    # Omitted, not sent as an empty value: the SDK drops nils before serializing, so this is what
    # keeps `"cc": []` off the wire.
    expect(mapped).not_to have_key(:cc)
    expect(mapped).not_to have_key(:bcc)
    expect(mapped).not_to have_key(:attachments)
    expect(mapped).not_to have_key(:html)
  end
end
