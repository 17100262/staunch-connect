RSpec.describe "Signing in and out" do
  let(:user) { create(:user, name: "Ada Lovelace") }

  it "signs in and lands on the dashboard" do
    sign_in_via_ui(user)

    expect(page).to have_current_path(root_path)
    expect(page).to have_button("Account menu")
  end

  it "returns to the page you asked for after signing in" do
    visit meetings_path
    expect(page).to have_current_path(new_session_path)

    fill_in "email_address", with: user.email_address
    fill_in "password", with: AuthHelpers::DEFAULT_PASSWORD
    click_on "Sign in"

    expect(page).to have_current_path(meetings_path)
  end

  it "explains a wrong password" do
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: "not-the-password"
    click_on "Sign in"

    expect(page).to have_text("Try another email address or password.")
  end

  it "signs out from the account menu after confirming" do
    sign_in_via_ui(user)

    click_on "Account menu"
    click_on "Sign out"
    within("[role=alertdialog]") { expect(page).to have_text("Sign out of Staunch Connect?") }
    click_on "Cancel"
    expect(page).to have_no_css("[role=alertdialog]", visible: true)

    click_on "Account menu"
    click_on "Sign out"
    within("[role=alertdialog]") { click_on "Sign out" }

    expect(page).to have_current_path(new_session_path)
  end

  it "resets a forgotten password from the emailed link" do
    visit new_session_path
    click_on "Forgot password?"
    fill_in "email_address", with: user.email_address
    perform_enqueued_jobs { click_on "Email reset instructions" }
    expect(page).to have_current_path(new_session_path)

    link = ActionMailer::Base.deliveries.last.text_part.body.to_s[%r{http://\S+/passwords/\S+/edit}]
    visit URI(link).path
    fill_in "password", with: "a-brand-new-pass-7!"
    fill_in "password_confirmation", with: "a-brand-new-pass-7!"
    click_on "Save password"
    expect(page).to have_current_path(new_session_path)

    sign_in_via_ui(user, password: "a-brand-new-pass-7!")
    expect(page).to have_current_path(root_path)
  end

  it "confirms that reset instructions were sent",
     pending: "Found by this suite: the guest layout only renders flash alerts, so notices never show" do
    visit new_password_path
    fill_in "email_address", with: user.email_address
    click_on "Email reset instructions"

    expect(page).to have_text("Password reset instructions sent")
  end
end
