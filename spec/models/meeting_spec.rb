RSpec.describe Meeting do
  subject { build(:meeting) }

  it { is_expected.to have_many(:transcript_chunks).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:fathom_recording_id) }
  it { is_expected.to validate_uniqueness_of(:fathom_recording_id).ignoring_case_sensitivity }

  describe ".search" do
    let!(:kickoff) { create(:meeting, title: "Acme kickoff", attendees: [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ]) }
    let!(:retro) { create(:meeting, title: "Sprint retro", attendees: [ { "name" => "Grace Hopper", "email" => "grace@client.com" } ]) }

    it "returns everything for a blank query" do
      expect(described_class.search("")).to contain_exactly(kickoff, retro)
    end

    it "matches the title case-insensitively" do
      expect(described_class.search("KICKOFF")).to contain_exactly(kickoff)
    end

    it "matches attendee names and emails" do
      expect(described_class.search("grace")).to contain_exactly(retro)
      expect(described_class.search("ada@staunch")).to contain_exactly(kickoff)
    end

    it "treats LIKE wildcards literally" do
      expect(described_class.search("%")).to be_empty
    end
  end

  it ".with_open_action_items finds meetings with an unfinished item" do
    open = create(:meeting, :with_action_items)
    create(:meeting, action_items: [ { "description" => "Done", "completed" => true } ])
    create(:meeting, action_items: [])

    expect(described_class.with_open_action_items).to contain_exactly(open)
  end

  it ".recorded_since filters by recording time" do
    recent = create(:meeting, recorded_at: 1.day.ago)
    create(:meeting, recorded_at: 40.days.ago)

    expect(described_class.recorded_since(7.days.ago)).to contain_exactly(recent)
  end

  it ".with_attendees matches on name or email" do
    ada = create(:meeting, attendees: [ { "name" => "Ada Lovelace", "email" => "ada@staunch.co" } ])
    grace = create(:meeting, attendees: [ { "name" => "Grace Hopper", "email" => "grace@client.com" } ])
    create(:meeting, attendees: [ { "name" => "Alan Turing" } ])

    expect(described_class.with_attendees([ "Ada Lovelace", "grace@client.com" ])).to contain_exactly(ada, grace)
  end

  it "#open_action_items drops completed ones" do
    meeting = build(:meeting, :with_action_items)

    expect(meeting.open_action_items.map { |i| i["description"] }).to eq([ "Send the release notes" ])
  end

  it "#attendee_names prefers the name and falls back to the email" do
    meeting = build(:meeting, attendees: [ { "name" => "Ada" }, { "name" => "", "email" => "x@y.z" }, {} ])

    expect(meeting.attendee_names).to eq([ "Ada", "x@y.z" ])
  end

  it "#processing? is true until Fathom delivers a summary or transcript" do
    expect(build(:meeting, :processing)).to be_processing
    expect(build(:meeting, summary: nil)).not_to be_processing
  end
end
