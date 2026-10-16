RSpec.describe User do
  subject { build(:user) }

  it { is_expected.to have_many(:sessions).dependent(:destroy) }
  it { is_expected.to have_many(:ai_conversations).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:email_address) }
  it { is_expected.to have_secure_password }

  it "rejects a malformed email address" do
    expect(build(:user, email_address: "not-an-email")).not_to be_valid
  end

  it "treats email addresses case-insensitively for uniqueness" do
    create(:user, email_address: "ada@staunch.co")

    expect(build(:user, email_address: " ADA@staunch.co ")).not_to be_valid
  end

  it "normalizes the email address, name and job title" do
    user = create(:user, email_address: "  Ada@Staunch.CO ", name: "  Ada ", job_title: "   ")

    expect(user).to have_attributes(email_address: "ada@staunch.co", name: "Ada", job_title: nil)
  end

  describe "#display_name" do
    it "uses the name when present" do
      expect(build(:user, name: "Grace Hopper").display_name).to eq("Grace Hopper")
    end

    it "falls back to a title-cased version of the email's local part" do
      expect(build(:user, name: nil, email_address: "grace.b_hopper@staunch.co").display_name).to eq("Grace B Hopper")
    end
  end

  it "derives first name and initials from the display name" do
    user = build(:user, name: "Grace Brewster Hopper")

    expect(user.first_name).to eq("Grace")
    expect(user.initials).to eq("GB")
  end

  describe "#time_zone_label" do
    it "labels known zones" do
      expect(build(:user, time_zone: "Asia/Karachi").time_zone_label).to eq("Pakistan Standard Time (GMT+5)")
    end

    it "shows unknown zones as-is" do
      expect(build(:user, time_zone: "Asia/Tokyo").time_zone_label).to eq("Asia/Tokyo")
    end

    it "says when nothing is set" do
      expect(build(:user, time_zone: nil).time_zone_label).to eq("Not set")
    end
  end

  describe ".password_problems" do
    it "lists every rule a weak password breaks" do
      expect(described_class.password_problems("short")).to contain_exactly(
        "At least 12 characters", "At least one number", "At least one symbol"
      )
    end

    it "is empty for a strong password" do
      expect(described_class.password_problems("correct-horse-battery-1!")).to be_empty
    end

    it "handles nil" do
      expect(described_class.password_problems(nil)).to include("At least 12 characters")
    end
  end
end
