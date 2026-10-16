RSpec.describe InvoiceLineItem do
  subject { build(:invoice_line_item) }

  it { is_expected.to belong_to(:invoice) }
  it { is_expected.to validate_presence_of(:title) }

  describe "#amount" do
    it "is rate times hours" do
      expect(build(:invoice_line_item, hourly_rate: 80, estimate_hours: 2.5).amount).to eq(200)
    end

    it "is zero when not billable" do
      expect(build(:invoice_line_item, :non_billable, hourly_rate: 80, estimate_hours: 2).amount).to eq(0)
    end

    it "treats a missing rate or estimate as zero" do
      expect(build(:invoice_line_item, hourly_rate: nil).amount).to eq(0)
      expect(build(:invoice_line_item, estimate_hours: nil).amount).to eq(0)
    end

    it "is rounded to cents", pending: "analysis.md #7: amounts are never rounded to cents" do
      item = create(:invoice_line_item, hourly_rate: 100, estimate_hours: BigDecimal("0.333333"))

      expect(item.amount).to eq(BigDecimal("33.33"))
    end
  end

  it "rejects negative hours and rates", pending: "analysis.md #8: negative values are accepted" do
    expect(build(:invoice_line_item, estimate_hours: -1)).not_to be_valid
    expect(build(:invoice_line_item, hourly_rate: -50)).not_to be_valid
  end
end
