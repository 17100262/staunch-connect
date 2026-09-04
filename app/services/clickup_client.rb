require "net/http"
require "uri"
require "json"

class ClickupClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = "https://api.clickup.com/api/v2"

  def initialize(token)
    @token = token
  end

  def verify!
    get("/user")
    true
  end

  def spaces(team_id)
    get("/team/#{team_id}/space")["spaces"]
  end

  def lists(space_id)
    get("/space/#{space_id}/list")["lists"]
  end

  def tasks(list_id)
    get("/list/#{list_id}/task")["tasks"]
  end

  private

  def get(path)
    uri = URI("#{BASE_URL}#{path}")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = @token

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise AuthenticationError, "ClickUp rejected this token."
    when Net::HTTPSuccess
      JSON.parse(response.body)
    else
      raise RequestError, "ClickUp request failed (#{response.code})."
    end
  end
end
