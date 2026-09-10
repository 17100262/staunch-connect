require "net/http"
require "uri"
require "json"

class VoyageClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = "https://api.voyageai.com/v1/embeddings"
  MODEL = "voyage-4"
  OUTPUT_DIMENSION = 1024
  MAX_RATE_LIMIT_RETRIES = 3

  def initialize(api_key)
    @api_key = api_key
  end

  # `input_type: "document"` — for text being indexed (see MeetingChunker/EmbedMeetingJob).
  def embed_documents(texts)
    embed(texts, input_type: "document")
  end

  # `input_type: "query"` — for a search query being matched against indexed documents.
  # Voyage's embeddings are asymmetric between the two input_types, so this distinction
  # matters for retrieval quality, not just documentation.
  def embed_query(text)
    embed([ text ], input_type: "query").first
  end

  private

  def embed(texts, input_type:)
    uri = URI(BASE_URL)
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = { input: texts, model: MODEL, input_type: input_type, output_dimension: OUTPUT_DIMENSION }.to_json

    perform(uri, request)
  end

  # Voyage's free/trial tier rate limit is easy to hit on a real backfill (confirmed while
  # testing this against 239 meetings) — retried with backoff, honoring `Retry-After` when
  # present, same pattern FathomClient already uses for its own rate limit.
  def perform(uri, request, attempt: 1)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPTooManyRequests
      raise RequestError, "Voyage AI rate-limited this request after #{MAX_RATE_LIMIT_RETRIES} attempts." if attempt >= MAX_RATE_LIMIT_RETRIES

      sleep(retry_after_seconds(response))
      perform(uri, request, attempt: attempt + 1)
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise AuthenticationError, "Voyage AI rejected this API key."
    when Net::HTTPSuccess
      JSON.parse(response.body)["data"].sort_by { |item| item["index"] }.map { |item| item["embedding"] }
    else
      raise RequestError, "Voyage AI request failed (#{response.code})."
    end
  end

  def retry_after_seconds(response)
    (response["Retry-After"] || response["RateLimit-Reset"]).to_i.clamp(1, 30)
  end
end
