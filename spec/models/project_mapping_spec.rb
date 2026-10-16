RSpec.describe ProjectMapping do
  subject { build(:project_mapping) }

  it { is_expected.to validate_presence_of(:clickup_space_id) }

  it "maps a folder to at most one project" do
    create(:project_mapping, clickup_folder_id: "folder_9")

    expect(build(:project_mapping, clickup_folder_id: "folder_9")).not_to be_valid
  end

  it "allows several folders in the same space" do
    create(:project_mapping, clickup_space_id: "space_9", clickup_folder_id: "a")

    expect(build(:project_mapping, clickup_space_id: "space_9", clickup_folder_id: "b")).to be_valid
  end

  it "allows only one folderless mapping per space" do
    create(:project_mapping, :space_only, clickup_space_id: "space_9")

    expect(build(:project_mapping, :space_only, clickup_space_id: "space_9")).not_to be_valid
  end

  it "refuses to be destroyed while it has invoices" do
    mapping = create(:invoice).project_mapping

    expect(mapping.destroy).to be(false)
    expect(mapping.errors[:base]).to be_present
  end
end
