RSpec.describe "Connections" do
  before { sign_in_as(create(:user)) }

  it "redirects the old index to the connectors settings" do
    get connections_path

    expect(response).to redirect_to(settings_path(section: "connectors"))
  end

  describe "connecting" do
    it "verifies and saves a ClickUp token" do
      stub_clickup_user

      post connections_path, params: { source: "clickup", credential: "pk_new" }

      expect(flash[:notice]).to eq("Clickup connected.")
      expect(Connection.find_by(source: "clickup")).to have_attributes(status: "connected", credential: "pk_new")
    end

    it "saves Hubstaff's rotated refresh token, not the one entered" do
      stub_hubstaff_token_refresh(rotated_to: "rotated-rt", access_token: "at")
      stub_hubstaff_organizations

      post connections_path, params: { source: "hubstaff", credential: "entered-rt" }

      expect(Connection.find_by(source: "hubstaff")).to have_attributes(credential: "rotated-rt", access_token: "at", status: "connected")
    end

    it "registers the Fathom webhook and keeps its secret" do
      stub_fathom_meetings
      webhook = stub_fathom_create_webhook(id: "wh_9", secret: "whsec_new")
        .with(body: hash_including("destination_url" => "http://www.example.com/webhooks/fathom"))

      post connections_path, params: { source: "fathom", credential: "fk" }

      expect(webhook).to have_been_requested
      expect(Connection.find_by(source: "fathom")).to have_attributes(webhook_id: "wh_9", webhook_secret: "whsec_new")
    end

    it "still connects Fathom when webhook registration fails" do
      stub_fathom_meetings
      stub_fathom_create_webhook(status: 400, error: "destination_url must be https")

      post connections_path, params: { source: "fathom", credential: "fk" }

      expect(Connection.find_by(source: "fathom")).to be_connected
      expect(flash[:notice]).to match(/Webhook registration failed \(.*must be https\)/)
    end

    it "verifies an Anthropic key" do
      stub_anthropic_models

      post connections_path, params: { source: "anthropic", credential: "sk-ant" }

      expect(Connection.find_by(source: "anthropic")).to be_connected
    end

    it "records a rejected credential as an error" do
      stub_clickup_user(status: 401)

      post connections_path, params: { source: "clickup", credential: "bad" }

      expect(flash[:alert]).to eq("ClickUp rejected this token.")
      expect(Connection.find_by(source: "clickup")).to have_attributes(status: "error", last_error: "ClickUp rejected this token.")
    end

    it "rejects unknown sources and blank credentials" do
      post connections_path, params: { source: "jira", credential: "x" }
      expect(flash[:alert]).to eq("Unknown source.")

      post connections_path, params: { source: "clickup", credential: "" }
      expect(flash[:alert]).to eq("Enter a credential.")
      expect(Connection.count).to eq(0)
    end
  end

  describe "syncing" do
    it "starts a background Fathom sync" do
      connection = create(:connection, :fathom)

      expect { post sync_connection_path(connection) }.to have_enqueued_job(FathomSyncJob).with(connection.id)
      expect(connection.reload).to be_syncing
    end

    it "returns to a local page it was started from, never an external one" do
      connection = create(:connection, :fathom)

      post sync_connection_path(connection), params: { return_to: "/meetings" }
      expect(response).to redirect_to("/meetings")

      post sync_connection_path(connection), params: { return_to: "//evil.example" }
      expect(response).to redirect_to(connections_path)
    end

    it "re-verifies ClickUp inline" do
      connection = create(:connection, :clickup, :errored)
      stub_clickup_user

      post sync_connection_path(connection)

      expect(flash[:notice]).to eq("Clickup synced.")
      expect(connection.reload).to have_attributes(status: "connected", last_error: nil)
    end

    it "persists Hubstaff's rotated token after a sync" do
      connection = create(:connection, :hubstaff)
      stub_hubstaff_token_refresh(rotated_to: "after-sync")
      stub_hubstaff_organizations

      post sync_connection_path(connection)

      expect(connection.reload.credential).to eq("after-sync")
    end

    it "keeps Hubstaff's rotated token when the sync fails after refreshing",
       pending: "analysis.md #6: mark_error never saves the rotated token" do
      connection = create(:connection, :hubstaff)
      stub_hubstaff_token_refresh(rotated_to: "after-sync")
      stub_hubstaff_organizations(status: 500)

      post sync_connection_path(connection)

      expect(connection.reload.credential).to eq("after-sync")
    end
  end

  it "disconnects and deregisters the Fathom webhook" do
    connection = create(:connection, :fathom, webhook_id: "wh_1")
    webhook = stub_fathom_delete_webhook("wh_1")

    delete connection_path(connection)

    expect(webhook).to have_been_requested
    expect(Connection.exists?(connection.id)).to be(false)
    expect(flash[:notice]).to eq("Fathom disconnected.")
  end

  it "still disconnects when Fathom refuses to delete the webhook" do
    connection = create(:connection, :fathom, webhook_id: "wh_1")
    stub_fathom_delete_webhook("wh_1", status: 500)

    delete connection_path(connection)

    expect(Connection.exists?(connection.id)).to be(false)
  end
end
