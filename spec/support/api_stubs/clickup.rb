module ApiStubs
  module Clickup
    CLICKUP = "https://api.clickup.com/api/v2".freeze

    def stub_clickup(path, body, status: 200, query: nil)
      request = stub_request(:get, "#{CLICKUP}#{path}")
      request = request.with(query: hash_including(query)) if query
      request.to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
    end

    def stub_clickup_user(status: 200)
      stub_clickup("/user", { user: { id: 1, username: "ada" } }, status: status)
    end

    # A workspace with one space, one folder holding two lists, and one folderless list.
    def stub_clickup_workspace(team_id: "team_1", space: { "id" => "space_1", "name" => "Acme" },
                               folder: { "id" => "folder_1", "name" => "Acme Website" },
                               lists: [ { "id" => "list_1", "name" => "Sprint 1" }, { "id" => "list_2", "name" => "Sprint 2" } ])
      stub_clickup("/team", { teams: [ { id: team_id, name: "Staunch" } ] })
      stub_clickup("/team/#{team_id}/space", { spaces: [ space ] })
      stub_clickup("/space/#{space['id']}/folder", { folders: [ folder.merge("lists" => lists) ] })
      stub_clickup("/space/#{space['id']}/list", { lists: [ { "id" => "list_loose", "name" => "Loose list" } ] })
    end

    def stub_clickup_tasks(list_id, tasks)
      stub_clickup("/list/#{list_id}/task", { tasks: tasks }, query: { "page" => "0" })
    end

    def clickup_task(id:, name:, hours: nil, parent: nil, custom_id: nil, custom_fields: [])
      { "id" => id, "name" => name, "custom_id" => custom_id, "parent" => parent,
        "time_estimate" => hours && (hours * 3_600_000).to_i, "custom_fields" => custom_fields }
    end
  end
end

RSpec.configure { |config| config.include ApiStubs::Clickup }
