require "net/http"
require "uri"
require "json"

class ClickupClient
  class AuthenticationError < StandardError; end
  class RequestError < StandardError; end

  BASE_URL = "https://api.clickup.com/api/v2"
  TASKS_PER_PAGE = 100

  # Workspace structure (teams, spaces, folders, lists) changes rarely but is
  # fetched on every "Create invoice" click, so it is cached briefly per process.
  # Tasks are never cached: reconciliation must reflect ClickUp right now.
  STRUCTURE_CACHE = ActiveSupport::Cache::MemoryStore.new(expires_in: 5.minutes)

  def initialize(token)
    @token = token
  end

  def verify!
    get("/user")
    true
  end

  def teams
    cached("/team") { get("/team")["teams"] }
  end

  def spaces(team_id)
    cached("/team/#{team_id}/space") { get("/team/#{team_id}/space")["spaces"] }
  end

  def folders(space_id)
    cached("/space/#{space_id}/folder") { get("/space/#{space_id}/folder")["folders"] }
  end

  def lists(space_id)
    cached("/space/#{space_id}/list") { get("/space/#{space_id}/list")["lists"] }
  end

  # Returns tasks and their subtasks as a single flat array — ClickUp distinguishes
  # them via the "parent" field (nil for a top-level task, the parent's id otherwise)
  # rather than nesting subtasks inside their parent.
  def tasks(list_id)
    tasks = []
    page = 0

    loop do
      batch = get("/list/#{list_id}/task", "include_closed" => "true", "subtasks" => "true", "page" => page)["tasks"]
      tasks.concat(batch)
      break if batch.size < TASKS_PER_PAGE

      page += 1
    end

    tasks
  end

  private

  def cached(path, &block)
    STRUCTURE_CACHE.fetch([ Digest::SHA256.hexdigest(@token.to_s), path ], &block)
  end

  def get(path, query = {})
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(query) if query.any?

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
