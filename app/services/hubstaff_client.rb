require "net/http"
require "uri"
require "json"

class HubstaffClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = "https://api.hubstaff.com/v2"

  def initialize(token)
    @token = token
  end

  def verify!
    get("/organizations")
    true
  end

  def organizations
    get("/organizations")["organizations"]
  end

  def projects(organization_id)
    get("/organizations/#{organization_id}/projects")["projects"]
  end

  def daily_activities(organization_id:, project_id:, date_from:, date_to:)
    get("/organizations/#{organization_id}/activities/daily", "project_ids" => project_id, "date" => date_from, "time_slot" => "#{date_from},#{date_to}")
  end

  private

  def get(path, query = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@token}"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPUnauthorized, Net::HTTPForbidden
      raise AuthenticationError, "Hubstaff rejected this token."
    when Net::HTTPSuccess
      JSON.parse(response.body)
    else
      raise RequestError, "Hubstaff request failed (#{response.code})."
    end
  end
end
