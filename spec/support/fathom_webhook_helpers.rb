module FathomWebhookHelpers
  WEBHOOK_SECRET = "whsec_#{Base64.strict_encode64("test-webhook-signing-key")}".freeze

  # Headers in the Standard Webhooks shape FathomWebhookVerifier checks.
  def signed_fathom_headers(body, secret: WEBHOOK_SECRET, id: "msg_#{SecureRandom.hex(4)}", timestamp: Time.current.to_i)
    key = Base64.decode64(secret.delete_prefix("whsec_"))
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{body}"))
    { "webhook-id" => id, "webhook-timestamp" => timestamp.to_s, "webhook-signature" => "v1,#{signature}" }
  end
end

RSpec.configure { |config| config.include FathomWebhookHelpers }
