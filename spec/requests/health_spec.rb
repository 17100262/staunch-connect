RSpec.describe "Health check" do
  it "reports the app is up without signing in" do
    get rails_health_check_path

    expect(response).to have_http_status(:ok)
  end
end
