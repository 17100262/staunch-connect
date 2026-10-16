RSpec.describe InvoicingAssistantTools do
  let(:acme) { create(:project_mapping, clickup_space_name: "Acme") }
  let(:globex) { create(:project_mapping, clickup_space_name: "Globex") }
  let!(:acme_sep) { create(:invoice, :with_line_items, project_mapping: acme, month: "2026-09", name: "Acme Sep") }
  let!(:acme_oct) { create(:invoice, project_mapping: acme, month: "2026-10", name: "Acme Oct") }
  let!(:globex_sep) { create(:invoice, project_mapping: globex, month: "2026-09", name: "Globex Sep") }

  before do
    create(:invoice_line_item, invoice: acme_oct, title: "Big task", estimate_hours: 40, hourly_rate: 50)
    create(:invoice_line_item, invoice: globex_sep, title: "Globex task", estimate_hours: 5, hourly_rate: 200)
  end

  def call(name, input = {})
    described_class.call(name, input)
  end

  it "defines a closed JSON schema for every tool it can call" do
    names = described_class.definitions.map { |d| d[:name] }

    expect(names).to contain_exactly("list_invoices", "get_invoice", "sum_amount", "top_line_item", "average_hourly_rate", "count_invoices")
    expect(described_class.definitions.map { |d| d.dig(:input_schema, :additionalProperties) }).to all(be(false))
  end

  it "accepts JSON-string input" do
    expect(call("count_invoices", '{"project":"acme"}')).to eq(count: 2)
  end

  it "reports an unknown tool" do
    expect(call("drop_table")).to eq(error: "Unknown tool 'drop_table'.")
  end

  describe "list_invoices" do
    it "summarises matching invoices" do
      result = call("list_invoices", "project" => "acme", "month_from" => "2026-09", "month_to" => "2026-09")

      expect(result[:invoices]).to eq([
        { name: "Acme Sep", month: "2026-09", project: "Acme", total_amount: 1250.0, total_estimate_hours: 13.5, line_item_count: 3 }
      ])
    end
  end

  describe "project matching" do
    it "says when no project matches" do
      expect(call("count_invoices", "project" => "Initech")).to eq(ambiguous: true, reason: "No project matched 'Initech'.")
    end

    it "asks which project when several match" do
      create(:project_mapping, clickup_space_name: "Acme Labs")

      result = call("count_invoices", "project" => "acme")

      expect(result).to include(ambiguous: true)
      expect(result[:candidates]).to contain_exactly("Acme", "Acme Labs")
    end
  end

  describe "get_invoice" do
    it "returns every line item for one project-month" do
      result = call("get_invoice", "project" => "Acme", "month" => "2026-09")

      expect(result[:found]).to be(true)
      expect(result[:invoice][:line_items].map { |i| i[:title] }).to contain_exactly("Build homepage", "Fix login", "Internal sync")
      expect(result[:invoice][:line_items].find { |i| i[:title] == "Internal sync" }).to include(billable: false, amount: 0.0)
    end

    it "requires a month" do
      expect(call("get_invoice", "project" => "Acme")).to eq(error: "month is required, formatted YYYY-MM.")
    end

    it "asks which project when several have that month" do
      result = call("get_invoice", "month" => "2026-09")

      expect(result).to include(ambiguous: true, candidates: contain_exactly("Acme", "Globex"))
    end

    it "says when nothing was found" do
      expect(call("get_invoice", "project" => "Acme", "month" => "2025-01")[:found]).to be(false)
    end
  end

  it "sum_amount totals billable amounts across matches" do
    result = call("sum_amount", "month_from" => "2026-09", "month_to" => "2026-09")

    expect(result).to include(total_amount: 2250.0, invoice_count: 2)
  end

  describe "top_line_item" do
    it "ranks by estimated hours" do
      result = call("top_line_item", "metric" => "estimate_hours", "n" => 2)

      expect(result[:results].map { |r| r[:title] }).to eq([ "Big task", "Build homepage" ])
      expect(result[:results].first).to include(invoice_name: "Acme Oct", project: "Acme", estimate_hours: 40.0)
    end

    it "clamps n to 20" do
      expect(call("top_line_item", "metric" => "estimate_hours", "n" => 500)[:results].size).to eq(5)
    end

    it "refuses metrics that don't exist yet" do
      expect(call("top_line_item", "metric" => "logged_hours")[:error]).to match(/Unsupported metric/)
    end
  end

  it "average_hourly_rate averages line-item rates" do
    expect(call("average_hourly_rate", "project" => "Globex")).to eq(average_hourly_rate: 200.0, line_item_count: 1)
  end

  it "count_invoices respects the month range" do
    expect(call("count_invoices", "month_from" => "2026-10")).to eq(count: 1)
  end

  it "never runs input as SQL" do
    expect(call("count_invoices", "project" => "'; DROP TABLE invoices; --")).to include(ambiguous: true)
    expect(Invoice.count).to eq(3)
  end
end
