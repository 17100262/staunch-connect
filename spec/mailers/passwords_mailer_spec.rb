RSpec.describe PasswordsMailer do
  it "sends a reset link to the user" do
    user = create(:user, email_address: "ada@staunch.co")

    mail = described_class.reset(user)

    expect(mail.to).to eq([ "ada@staunch.co" ])
    expect(mail.subject).to eq("Reset your password")
    expect(mail.body.encoded).to match(%r{/passwords/[^/]+/edit})
  end
end
