require "openssl"
require "base64"

# Verifies a Fathom webhook delivery against its signing secret. Fathom uses
# the same scheme as the Standard Webhooks/Svix convention (confirmed at build
# time via developers.fathom.ai/webhooks): `webhook-id`, `webhook-timestamp`,
# and `webhook-signature` headers, a `whsec_`-prefixed base64 secret, and a
# signed payload of `"#{id}.#{timestamp}.#{raw_body}"` HMAC-SHA256'd and
# base64-encoded. This is the one endpoint in the app reachable without
# logging in (Section 5.2/7 of FATHOM_INTEGRATION_SPEC.md), so verification
# failures must reject the request rather than let it through unverified.
class FathomWebhookVerifier
  class InvalidSignature < StandardError; end

  TOLERANCE = 5.minutes

  def initialize(secret)
    @key = Base64.decode64(secret.to_s.delete_prefix("whsec_"))
  end

  def verify!(id:, timestamp:, signature_header:, raw_body:)
    if id.blank? || timestamp.blank? || signature_header.blank?
      raise InvalidSignature, "Missing webhook signature headers."
    end

    if (Time.current.to_i - timestamp.to_i).abs > TOLERANCE
      raise InvalidSignature, "Webhook timestamp outside tolerance."
    end

    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", @key, "#{id}.#{timestamp}.#{raw_body}"))
    signatures = signature_header.to_s.split(" ").map { |part| part.split(",", 2).last }

    unless signatures.any? { |signature| ActiveSupport::SecurityUtils.secure_compare(signature, expected) }
      raise InvalidSignature, "Webhook signature did not match."
    end

    true
  end
end
