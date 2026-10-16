# The dashboard: what was billed, what needs a look, and what is new. Everything
# comes from data already in the app (saved invoices, synced meetings); nothing
# here calls ClickUp, Hubstaff or Fathom.
class HomeController < ApplicationController
  CHART_MONTHS = 6
  DONUT_COLORS = %w[var(--bg-primary) var(--fg-success) var(--fg-warning) var(--fg-info) var(--border-strong)].freeze
  SOURCE_LABELS = { "hubstaff" => "Hubstaff", "clickup" => "ClickUp", "fathom" => "Fathom" }.freeze

  def index
    load_sources
    load_invoice_figures
    load_meetings
  end

  private

  def load_sources
    connected = Connection.where(status: %w[connected syncing]).pluck(:source)
    @connected_sources = connected
    @missing_sources = Connection::SOURCES - connected
    @nothing_connected = connected.empty?
  end

  def load_invoice_figures
    today = Date.current
    @month = today.strftime("%Y-%m")
    @month_label = today.strftime("%B %Y")
    months = (0...CHART_MONTHS).map { |i| (today.beginning_of_month - (CHART_MONTHS - 1 - i).months) }

    invoices = Invoice.where(month: months.map { |d| d.strftime("%Y-%m") }).includes(:project_mapping, :invoice_line_items).to_a
    by_month = invoices.group_by(&:month)

    @chart = months.map do |date|
      key = date.strftime("%Y-%m")
      { key: key, label: date.strftime("%b"), total: (by_month[key] || []).sum { |i| i.total_amount.to_f } }
    end

    this_month = by_month[@month] || []
    last_key = (today.beginning_of_month - 1.month).strftime("%Y-%m")
    last_month = by_month[last_key] || []

    @billed_this_month = this_month.sum { |i| i.total_amount.to_f }
    @billed_last_month = last_month.sum { |i| i.total_amount.to_f }
    @invoice_count = this_month.size
    @hours_this_month = this_month.sum { |i| i.invoice_line_items.select(&:billable).sum { |l| l.estimate_hours.to_f } }
    @hours_last_month = last_month.sum { |i| i.invoice_line_items.select(&:billable).sum { |l| l.estimate_hours.to_f } }

    by_project = this_month.group_by { |i| i.project_mapping.clickup_folder_name.presence || i.project_mapping.clickup_space_name.presence || i.name }
    ranked = by_project.map { |name, list| [ name, list.size ] }.sort_by { |_, count| -count }
    top = ranked.first(DONUT_COLORS.size - 1)
    rest = ranked.drop(top.size).sum { |_, count| count }
    top << [ "Other", rest ] if rest.positive?
    @donut = top.each_with_index.map { |(name, count), i| { name: name, count: count, color: DONUT_COLORS[i] } }

    @attention = attention_items(this_month + last_month)
  end

  # Saved invoices that would produce a wrong or incomplete bill.
  def attention_items(invoices)
    invoices.sort_by(&:month).reverse.filter_map do |invoice|
      billable = invoice.invoice_line_items.select(&:billable)
      no_rate = billable.count { |l| l.hourly_rate.to_f.zero? }
      no_estimate = billable.count { |l| l.estimate_hours.to_f.zero? }
      problems = []
      problems << "#{no_rate} #{'line'.pluralize(no_rate)} without a rate" if no_rate.positive?
      problems << "#{no_estimate} #{'task'.pluralize(no_estimate)} without an estimate" if no_estimate.positive?
      next if problems.empty?

      { invoice: invoice, label: problems.first, detail: problems.join(" · ") }
    end.first(5)
  end

  def load_meetings
    @new_meetings_count = Meeting.where(recorded_at: 7.days.ago..).count
    @recent_meetings = Meeting.order(recorded_at: :desc).limit(3)
  end
end
