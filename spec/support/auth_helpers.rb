module AuthHelpers
  DEFAULT_PASSWORD = "correct-horse-battery-1!".freeze

  # Request specs: signs in through the real sessions endpoint so the signed cookie is set.
  def sign_in_as(user, password: DEFAULT_PASSWORD)
    post session_path, params: { email_address: user.email_address, password: password }
  end
end

module SystemAuthHelpers
  def sign_in_via_ui(user, password: AuthHelpers::DEFAULT_PASSWORD)
    visit new_session_path
    fill_in "email_address", with: user.email_address
    fill_in "password", with: password
    click_on "Sign in"
    expect(page).to have_no_current_path(new_session_path)
  end
end

RSpec.configure do |config|
  config.include AuthHelpers, type: :request
  config.include SystemAuthHelpers, type: :system
end
