require "anthropic"

# Checks an Anthropic API key (the AI Assistant's key from Settings > Connectors)
# with a cheap call, in the same shape as the other connector clients so
# ConnectionsController can treat it like them.
class AnthropicConnection
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  def initialize(api_key)
    @api_key = api_key
  end

  def verify!
    Anthropic::Client.new(api_key: @api_key, max_retries: 1, timeout: 15).models.list(limit: 1)
    true
  rescue Anthropic::Errors::AuthenticationError, Anthropic::Errors::PermissionDeniedError
    raise AuthenticationError, "Anthropic rejected this API key. Check it and try again."
  rescue Anthropic::Errors::APIError => e
    raise RequestError, "Couldn't reach Anthropic to check the key: #{e.message}"
  end
end
