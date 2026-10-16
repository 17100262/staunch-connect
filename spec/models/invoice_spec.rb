RSpec.describe Invoice do
  subject { build(:invoice) }

  it { is_expected.to belong_to(:project_mapping) }
  it { is_expected.to have_many(:invoice_line_items).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:month) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to accept_nested_attributes_for(:invoice_line_items) }

  it "allows one invoice per project per month" do
    existing = create(:invoice, month: "2026-09")

    expect(build(:invoice, project_mapping: existing.project_mapping, month: "2026-09")).not_to be_valid
    expect(build(:invoice, month: "2026-09")).to be_valid
  end

  describe "totals" do
    let(:invoice) { create(:invoice, :with_line_items) }

    it "sums billable amounts only" do
      expect(invoice.total_amount).to eq(1250)
    end

    it "sums estimated hours across every line item, billable or not" do
      expect(invoice.total_estimate_hours).to eq(13.5)
    end

    it "counts missing estimates as zero" do
      create(:invoice_line_item, invoice: invoice, estimate_hours: nil)

      expect(invoice.reload.total_estimate_hours).to eq(13.5)
    end

    it "rounds the total to cents", pending: "analysis.md #7: amounts are never rounded to cents" do
      empty = create(:invoice)
      3.times { create(:invoice_line_item, invoice: empty, hourly_rate: 100, estimate_hours: BigDecimal("0.333333")) }

      expect(empty.total_amount).to eq(BigDecimal("99.99"))
    end
  end
end
