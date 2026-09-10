module Webhooks
  # Public — called directly by Fathom's servers, not by a logged-in browser
  # session, so it's exempted from both the app's login requirement and CSRF
  # protection (neither applies to a server-to-server webhook). Signature
  # verification (FathomWebhookVerifier) is what stands in for both of those
  # here, so it is not optional — see FATHOM_INTEGRATION_SPEC.md Section 5.2/7.
  class FathomController < ApplicationController
    allow_unauthenticated_access only: %i[create]
    skip_before_action :verify_authenticity_token, only: %i[create]

    def create
      connection = Connection.find_by(source: "fathom")
      return head :not_found if connection&.webhook_secret.blank?

      raw_body = request.raw_post

      FathomWebhookVerifier.new(connection.webhook_secret).verify!(
        id: request.headers["webhook-id"],
        timestamp: request.headers["webhook-timestamp"],
        signature_header: request.headers["webhook-signature"],
        raw_body: raw_body
      )

      Fathom::MeetingSync.call(JSON.parse(raw_body))
      connection.update!(last_used_at: Time.current, last_error: nil)

      head :ok
    rescue FathomWebhookVerifier::InvalidSignature
      head :unauthorized
    rescue JSON::ParserError
      head :bad_request
    end
  end
end
