RSpec.describe "Authentication" do
  let(:user) { create(:user) }

  it "sends signed-out visitors to the sign-in page and back afterwards" do
    get meetings_path
    expect(response).to redirect_to(new_session_path)

    sign_in_as(user)
    expect(response).to redirect_to(meetings_url)
  end

  it "signs in with valid credentials and creates a session" do
    expect { sign_in_as(user) }.to change(user.sessions, :count).by(1)
    expect(response).to redirect_to(root_url)

    get root_path
    expect(response).to have_http_status(:ok)
  end

  it "rejects a wrong password" do
    sign_in_as(user, password: "wrong")

    expect(response).to redirect_to(new_session_path)
    expect(flash[:alert]).to eq("Try another email address or password.")
  end

  it "signs out" do
    sign_in_as(user)

    delete session_path

    expect(response).to redirect_to(new_session_path)
    expect(user.sessions.count).to eq(0)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "renders the sign-in page" do
    get new_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in")
  end
end

RSpec.describe "Password reset" do
  let(:user) { create(:user) }

  it "emails reset instructions to a known address" do
    expect { post passwords_path, params: { email_address: user.email_address } }
      .to have_enqueued_mail(PasswordsMailer, :reset)
    expect(response).to redirect_to(new_session_path)
  end

  it "gives the same answer for an unknown address" do
    expect { post passwords_path, params: { email_address: "nobody@staunch.co" } }.not_to have_enqueued_mail
    expect(response).to redirect_to(new_session_path)
  end

  it "resets the password with a valid token and signs out other sessions" do
    create(:session, user: user)

    get edit_password_path(user.password_reset_token)
    expect(response).to have_http_status(:ok)

    put password_path(user.password_reset_token), params: { password: "new-password-123!", password_confirmation: "new-password-123!" }

    expect(response).to redirect_to(new_session_path)
    expect(user.reload.authenticate("new-password-123!")).to be_truthy
    expect(user.sessions).to be_empty
  end

  it "rejects mismatched passwords" do
    put password_path(user.password_reset_token), params: { password: "a-password-123!", password_confirmation: "different" }

    expect(response).to redirect_to(%r{/passwords/.+/edit})
    expect(flash[:alert]).to eq("Passwords did not match.")
  end

  it "rejects an invalid token" do
    get edit_password_path("forged")

    expect(response).to redirect_to(new_password_path)
    expect(flash[:alert]).to match(/invalid or has expired/)
  end
end
