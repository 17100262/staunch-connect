RSpec.describe ClickupClient do
  subject(:client) { described_class.new("pk_test_token") }

  it "verifies the token against /user and sends it raw in Authorization" do
    stub = stub_clickup_user.with(headers: { "Authorization" => "pk_test_token" })

    expect(client.verify!).to be(true)
    expect(stub).to have_been_requested
  end

  it "maps 401 and 403 to AuthenticationError" do
    stub_clickup_user(status: 401)

    expect { client.verify! }.to raise_error(described_class::AuthenticationError)
  end

  it "maps other failures to RequestError with the status code" do
    stub_clickup_user(status: 503)

    expect { client.verify! }.to raise_error(described_class::RequestError, /503/)
  end

  it "reads teams, spaces, folders and lists" do
    stub_clickup_workspace

    expect(client.teams.first["id"]).to eq("team_1")
    expect(client.spaces("team_1").first["name"]).to eq("Acme")
    expect(client.folders("space_1").first["lists"].size).to eq(2)
    expect(client.lists("space_1").first["id"]).to eq("list_loose")
  end

  it "caches workspace structure per token" do
    stub = stub_clickup("/team", { teams: [ { id: "t" } ] })

    2.times { client.teams }
    described_class.new("another-token").teams

    expect(stub).to have_been_requested.twice
  end

  it "pages through tasks, including subtasks and closed tasks" do
    first_page = Array.new(100) { |i| clickup_task(id: "t#{i}", name: "Task #{i}") }
    stub_clickup("/list/list_1/task", { tasks: first_page }, query: { "page" => "0", "subtasks" => "true", "include_closed" => "true" })
    stub_clickup("/list/list_1/task", { tasks: [ clickup_task(id: "last", name: "Last") ] }, query: { "page" => "1" })

    expect(client.tasks("list_1").size).to eq(101)
  end

  it "never caches tasks" do
    stub = stub_clickup_tasks("list_1", [])

    2.times { client.tasks("list_1") }

    expect(stub).to have_been_requested.twice
  end
end
