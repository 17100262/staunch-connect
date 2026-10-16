RSpec.describe "Settings" do
  let(:user) { create(:user, name: "Ada Lovelace") }

  before { sign_in_via_ui(user) }

  def open_settings(section = nil)
    click_on "Account menu"
    within("[role=menu][aria-label=Account]") { click_on "Settings" }
    expect(page).to have_css("[role=dialog] #sm2-t", text: "Profile")
    within("nav[aria-label='Settings sections']") { click_on section } if section
  end

  it "edits the profile inline" do
    open_settings

    within("section[aria-label=Profile]") do
      first(:button, "Edit").click
      fill_in "e-name", with: "Grace Hopper"
      click_on "Save"
    end

    expect(page).to have_text("Profile saved.")
    expect(user.reload.name).to eq("Grace Hopper")
  end

  it "closes with the close button" do
    open_settings
    click_on "Close settings"

    expect(page).to have_no_css("[role=dialog] #sm2-t")
  end

  it "only enables Update password once the rules are met and the passwords match" do
    open_settings("Password")

    within("section[aria-label=Password]") do
      fill_in "pw-cur", with: AuthHelpers::DEFAULT_PASSWORD
      fill_in "pw-new", with: "short"
      expect(page).to have_button("Update password", disabled: true)

      fill_in "pw-new", with: "a-much-longer-pass-1!"
      fill_in "pw-con", with: "something-else-2!"
      expect(page).to have_text("Passwords do not match.")
      expect(page).to have_button("Update password", disabled: true)

      fill_in "pw-con", with: "a-much-longer-pass-1!"
      click_on "Update password"
    end

    expect(page).to have_text("Password updated.")
    expect(user.reload.authenticate("a-much-longer-pass-1!")).to be_truthy
  end

  describe "connectors" do
    it "connects ClickUp with a token" do
      stub_clickup_user
      open_settings("Connectors")

      within("article[aria-label=ClickUp]") do
        click_on "Connect"
        fill_in "tok-clickup", with: "pk_live"
        click_on "Connect ClickUp"
      end

      within("article[aria-label=ClickUp]") { expect(page).to have_text("Connected") }
      expect(Connection.find_by(source: "clickup")).to be_connected
    end

    it "shows a rejected token and lets you reconnect" do
      stub_clickup_user(status: 401)
      open_settings("Connectors")

      within("article[aria-label=ClickUp]") do
        click_on "Connect"
        fill_in "tok-clickup", with: "bad"
        click_on "Connect ClickUp"
      end

      within("article[aria-label=ClickUp]") do
        expect(page).to have_text("Needs attention")
        expect(page).to have_text("ClickUp rejected this token.")
        expect(page).to have_button("Reconnect")
      end
    end

    it "starts a Fathom sync" do
      create(:connection, :fathom)
      open_settings("Connectors")

      within("article[aria-label=Fathom]") do
        expect(page).to have_text("Webhook registered")
        click_on "Sync Fathom now"
      end

      expect(page).to have_text("Fathom sync started in the background")
      expect(Connection.find_by(source: "fathom")).to be_syncing
    end

    it "disconnects after confirming" do
      create(:connection, :clickup)
      open_settings("Connectors")

      within("article[aria-label=ClickUp]") do
        click_on "More actions for ClickUp"
        accept_confirm("Disconnect ClickUp? Synced data stays.") { click_on "Disconnect" }
      end

      expect(page).to have_text("Clickup disconnected.")
      expect(Connection.exists?(source: "clickup")).to be(false)
    end
  end
end
