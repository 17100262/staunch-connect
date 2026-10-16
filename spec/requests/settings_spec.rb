RSpec.describe "Settings" do
  let(:user) { create(:user) }
  let(:frame) { { "Turbo-Frame" => "modal" } }

  before { sign_in_as(user) }

  it "opens over the home page on a direct visit",
     pending: "Found by this suite: SettingsController#show renders home/index without loading its data (500)" do
    get settings_path(section: "password")

    expect(response).to have_http_status(:ok)
  end

  it "renders each section inside the modal frame" do
    %w[profile password notifications connectors].each do |section|
      get settings_path(section: section), headers: frame

      expect(response).to have_http_status(:ok), "section #{section}"
    end
  end

  it "lists every connector, connected or not" do
    create(:connection, :fathom)

    get settings_path(section: "connectors"), headers: frame

    expect(response.body).to include("Fathom", "ClickUp", "Hubstaff", "Anthropic")
  end

  describe "profile" do
    it "saves changes" do
      patch settings_profile_path, params: { user: { name: "Grace Hopper", job_title: "Engineer", time_zone: "Asia/Dubai" } }

      expect(response).to redirect_to(settings_path(section: "profile"))
      expect(user.reload).to have_attributes(name: "Grace Hopper", job_title: "Engineer", time_zone: "Asia/Dubai")
    end

    it "explains invalid input" do
      patch settings_profile_path, params: { user: { email_address: "nope" } }

      expect(flash[:alert]).to match(/Email address is invalid/)
    end
  end

  describe "password" do
    def change_password(current: AuthHelpers::DEFAULT_PASSWORD, new: "brand-new-pass-9!", confirm: new)
      patch settings_password_path, params: { current_password: current, password: new, password_confirmation: confirm }
    end

    it "updates the password" do
      change_password

      expect(flash[:notice]).to eq("Password updated.")
      expect(user.reload.authenticate("brand-new-pass-9!")).to be_truthy
    end

    it "requires the current password" do
      change_password(current: "wrong")

      expect(flash[:alert]).to eq("Your current password isn't right.")
    end

    it "requires a matching confirmation" do
      change_password(confirm: "something-else-1!")

      expect(flash[:alert]).to eq("The new passwords don't match.")
    end

    it "enforces the password rules" do
      change_password(new: "short")

      expect(flash[:alert]).to eq("Your new password needs: at least 12 characters, at least one number, and at least one symbol.")
    end
  end
end
