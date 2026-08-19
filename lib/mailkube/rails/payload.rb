# frozen_string_literal: true

module Mailkube
  module Rails
    # The one place a `Mail::Message` becomes SDK send arguments.
    #
    # Every entry point calls {build}; nothing else maps a message. A gem with two entry points and
    # two mappings has two behaviours, and only one of them is the one the tests cover.
    #
    # Scope is deliberately what ActionMailer's message type natively expresses: sender,
    # recipients, subject, both bodies, attachments and custom headers. Tags, topics, templates,
    # scheduling and idempotency keys are SDK features with no `Mail::Message` slot, so inventing a
    # side channel for them here would create a second surface to document and test. Reach them by
    # calling the SDK directly; the README says so.
    module Payload
      # Header names ActionMailer derives from the message itself.
      #
      # These are re-created by the API from the structured fields this mapping already sends, so
      # forwarding them as "custom" headers would contradict what the API builds. `content-type` is
      # the one that matters: it describes a MIME document that is never transmitted, because this
      # gem hands over fields rather than a rendered message.
      RESERVED_HEADERS = %w[
        bcc cc content-transfer-encoding content-type date from
        message-id mime-version reply-to subject to
      ].freeze

      # Convert a message into the keyword arguments for `client.emails.send`.
      #
      # @param message [Mail::Message] the message ActionMailer built.
      # @return [Hash{Symbol => Object}] the SDK send keywords.
      def self.build(message)
        {
          from: addresses(message, :from).first,
          to: addresses(message, :to),
          subject: message.subject.to_s,
          html: body_for(message, "text/html"),
          text: body_for(message, "text/plain"),
          cc: presence(addresses(message, :cc)),
          bcc: presence(addresses(message, :bcc)),
          reply_to: presence(addresses(message, :reply_to)),
          headers: presence(custom_headers(message)),
          attachments: presence(attachments(message))
        }.compact
      end

      # Render one address field as RFC strings, keeping display names.
      #
      # **Read through `message[field]`, not through `message.to_addrs`.** The `*_addrs` readers
      # return BARE addresses, so a display name is already gone by the time this sees them and no
      # amount of re-parsing brings it back. `Mail::Field#addrs` returns the parsed address objects,
      # and `.format` renders each one as the application wrote it.
      #
      # `*_addrs` is also incomplete: `from_addrs`, `to_addrs`, `cc_addrs` and `bcc_addrs` exist but
      # there is no `reply_to_addrs`, so that one reaches `method_missing` and raises. Going through
      # the field object treats all five identically and cannot develop that asymmetry.
      #
      # @param message [Mail::Message] the message.
      # @param field [Symbol] the header field name.
      # @return [Array<String>] the formatted addresses, empty when the field is absent.
      def self.addresses(message, field)
        header = message[field]
        return [] if header.nil?

        # The annotation is what makes this checkable. `header` is untyped (the framework side is
        # deliberately shallow in sig/vendor/), so without it the element type erases to `bot` and
        # Steep rejects `&:format` while RuboCop insists on it — the two gates deadlock. Naming the
        # type resolves both, and it is the one place this gem asserts what `Mail` hands back.
        addrs = header.addrs #: Array[::Mail::Address]
        addrs.map(&:format)
      end

      # Extract one body part as decoded text.
      #
      # `.decoded`, never `.raw_source`: a quoted-printable or base64 body would otherwise ship its
      # transfer encoding to the API verbatim, and the recipient would read `=3D` where an equals
      # sign belongs.
      #
      # @param message [Mail::Message] the message.
      # @param mime_type [String] the part's MIME type.
      # @return [String, nil] the decoded body, or nil when the message has no such part.
      def self.body_for(message, mime_type)
        part = part_for(message, mime_type)
        return nil if part.nil?

        # `.decoded` undoes the transfer encoding but hands back ASCII-8BIT bytes, with the part's
        # charset recorded separately. Passing those to JSON either raises on invalid byte sequences
        # or ships mojibake, so the bytes are reunited with their declared charset here. `charset`
        # can be absent on a bare message, and UTF-8 is the only sane assumption when it is.
        presence(transcode(part.body.decoded, part.charset))
      end

      # Reinterpret decoded bytes in the charset the part declared.
      #
      # @param body [String] the decoded bytes.
      # @param charset [String, nil] the part's declared charset.
      # @return [String] the body as UTF-8 text.
      def self.transcode(body, charset)
        body.dup.force_encoding(charset || "UTF-8").encode("UTF-8")
      rescue ArgumentError, EncodingError
        # An unknown or lying charset must not stop the send. The bytes go out as they arrived,
        # which is what any non-transcoding mapping would have done anyway.
        body
      end

      # Find the part carrying one MIME type, or nil.
      #
      # Split out of {body_for} so the branch has somewhere to return `untyped` from: written
      # inline, the `if`/`elsif` has no `else` arm and Steep infers `bot` for the result, making the
      # decode below unreachable in its eyes.
      #
      # @param message [Mail::Message] the message.
      # @param mime_type [String] the part's MIME type.
      # @return [Object, nil] the matching part, or nil.
      def self.part_for(message, mime_type)
        return message.all_parts.find { |part| part.mime_type == mime_type && !part.attachment? } if message.multipart?
        return message if message.mime_type == mime_type
        return message if mime_type == "text/plain" && message.mime_type.nil?

        nil
      end

      # Convert the message's attachments into SDK attachments.
      #
      # `.body.decoded` hands over the original bytes; the SDK base64-encodes them for the wire.
      # Encoding here would send them twice over.
      #
      # @param message [Mail::Message] the message.
      # @return [Array<Mailkube::Attachment>] the attachments.
      def self.attachments(message)
        message.attachments.map do |attachment|
          Mailkube::Attachment.new(
            filename: attachment.filename.to_s,
            content: attachment.body.decoded,
            content_type: attachment.mime_type
          )
        end
      end

      # Collect the headers the application set itself.
      #
      # @param message [Mail::Message] the message.
      # @return [Hash{String => String}] the custom headers.
      def self.custom_headers(message)
        headers = {} #: Hash[String, String]
        message.header.fields.each do |field|
          next if RESERVED_HEADERS.include?(field.name.to_s.downcase)

          headers[field.name.to_s] = field.value.to_s
        end
        headers
      end

      # Treat an empty string, array or hash as absent.
      #
      # An unset field is **omitted** from the send rather than passed as an empty value: the SDK
      # drops nils before serializing, so this is what keeps an empty `cc` off the wire instead of
      # sending `"cc": []`.
      #
      # @param value [Object, nil] the mapped value.
      # @return [Object, nil] the value, or nil when it is empty.
      def self.presence(value)
        return nil if value.nil?
        return nil if value.respond_to?(:empty?) && value.empty?

        value
      end
    end
  end
end
