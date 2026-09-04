require "net/http"
require "uri"
require "json"

class HubstaffClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  TOKEN_URL = URI("https://account.hubstaff.com/access_tokens")
  BASE_URL = "https://api.hubstaff.com/v2"

  attr_reader :refresh_token, :access_token, :access_token_expires_at

  # `refresh_token` is what Hubstaff calls a "Personal Access Token" — it isn't usable
  # directly as a Bearer token, it must be exchanged for a short-lived access token first.
  # Every exchange also rotates the refresh token, so the caller must persist the new
  # value from `refresh_token` after a successful call, or the next exchange will fail.
  def initialize(refresh_token, access_token: nil, access_token_expires_at: nil)
    @refresh_token = refresh_token
    @access_token = access_token
    @access_token_expires_at = access_token_expires_at
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
    ensure_access_token!

    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@access_token}"

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

  def ensure_access_token!
    return if @access_token.present? && @access_token_expires_at.present? && @access_token_expires_at > 1.minute.from_now

    request = Net::HTTP::Post.new(TOKEN_URL)
    request.set_form_data("grant_type" => "refresh_token", "refresh_token" => @refresh_token)

    response = Net::HTTP.start(TOKEN_URL.host, TOKEN_URL.port, use_ssl: true) { |http| http.request(request) }

    case response
    when Net::HTTPUnauthorized, Net::HTTPForbidden, Net::HTTPBadRequest
      raise AuthenticationError, "Hubstaff rejected this token."
    when Net::HTTPSuccess
      body = JSON.parse(response.body)
      @access_token = body["access_token"]
      @refresh_token = body["refresh_token"]
      @access_token_expires_at = body["expires_in"].to_i.seconds.from_now
    else
      raise RequestError, "Hubstaff token exchange failed (#{response.code})."
    end
  end
end
