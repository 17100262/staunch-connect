# The AI Assistant's fixed query surface over invoicing data (AI_ASSISTANT_SPEC.md, Section 4).
# Every method here is read-only and only ever accepts named, validated arguments — never raw
# SQL or a column/table name — so the assistant can propose a tool call without any risk of an
# arbitrary or destructive query reaching the database.
class InvoicingAssistantTools
  SUPPORTED_METRICS = %w[estimate_hours].freeze

  class << self
    def definitions
      [
        {
          name: "list_invoices",
          description: "List invoices, optionally filtered by project name and/or a month range. Returns each invoice's name, month, project, total billed amount, total estimated hours, and line item count.",
          input_schema: {
            type: "object",
            properties: {
              project: project_property,
              month_from: month_property("Earliest month to include (inclusive)."),
              month_to: month_property("Latest month to include (inclusive).")
            },
            additionalProperties: false
          }
        },
        {
          name: "get_invoice",
          description: "Get full detail for one invoice — its total amount, total estimated hours, and every line item (title, ticket, hourly rate, estimated hours, billable flag, amount).",
          input_schema: {
            type: "object",
            properties: {
              project: project_property,
              month: month_property("The invoice's billing month.")
            },
            required: %w[month],
            additionalProperties: false
          }
        },
        {
          name: "sum_amount",
          description: "Sum the total billed amount (billable line items only) across invoices matching a project and/or month range.",
          input_schema: {
            type: "object",
            properties: {
              project: project_property,
              month_from: month_property("Earliest month to include (inclusive)."),
              month_to: month_property("Latest month to include (inclusive).")
            },
            additionalProperties: false
          }
        },
        {
          name: "top_line_item",
          description: "Find the line item(s) with the highest value for a metric, across invoices matching a project and/or month range. Only 'estimate_hours' is supported right now — there is no per-task 'hours actually logged' data yet, only the ClickUp estimate.",
          input_schema: {
            type: "object",
            properties: {
              metric: { type: "string", enum: SUPPORTED_METRICS, description: "Which field to rank by. Only 'estimate_hours' exists today." },
              project: project_property,
              month_from: month_property("Earliest month to include (inclusive)."),
              month_to: month_property("Latest month to include (inclusive)."),
              n: { type: "integer", minimum: 1, maximum: 20, description: "How many top line items to return. Defaults to 1." }
            },
            required: %w[metric],
            additionalProperties: false
          }
        },
        {
          name: "average_hourly_rate",
          description: "Average the hourly rate across line items matching a project and/or month range.",
          input_schema: {
            type: "object",
            properties: {
              project: project_property,
              month_from: month_property("Earliest month to include (inclusive)."),
              month_to: month_property("Latest month to include (inclusive).")
            },
            additionalProperties: false
          }
        },
        {
          name: "count_invoices",
          description: "Count invoices matching a project and/or month range.",
          input_schema: {
            type: "object",
            properties: {
              project: project_property,
              month_from: month_property("Earliest month to include (inclusive)."),
              month_to: month_property("Latest month to include (inclusive).")
            },
            additionalProperties: false
          }
        }
      ]
    end

    def call(name, input)
      input = input.is_a?(String) ? JSON.parse(input) : input.stringify_keys

      case name
      when "list_invoices" then list_invoices(input)
      when "get_invoice" then get_invoice(input)
      when "sum_amount" then sum_amount(input)
      when "top_line_item" then top_line_item(input)
      when "average_hourly_rate" then average_hourly_rate(input)
      when "count_invoices" then count_invoices(input)
      else { error: "Unknown tool '#{name}'." }
      end
    rescue ArgumentError => e
      { error: "Invalid arguments: #{e.message}" }
    end

    private

    def project_property
      { type: "string", description: "Project name to filter by (matched loosely against the ClickUp space name). Omit to include every project." }
    end

    def month_property(description)
      { type: "string", pattern: '^\d{4}-\d{2}$', description: "#{description} Format: YYYY-MM." }
    end

    def list_invoices(input)
      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      {
        invoices: scope.map { |invoice| invoice_summary(invoice) }
      }
    end

    def get_invoice(input)
      month = input["month"]
      return { error: "month is required, formatted YYYY-MM." } if month.blank?

      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      matches = scope.where(month: month).to_a

      case matches.size
      when 0
        { found: false, reason: "No invoice found for month #{month}#{" and project '#{input["project"]}'" if input["project"].present?}." }
      when 1
        { found: true, invoice: invoice_detail(matches.first) }
      else
        { ambiguous: true, reason: "Multiple projects have an invoice for #{month} — ask which one.", candidates: matches.map { |invoice| invoice.project_mapping.clickup_space_name } }
      end
    end

    def sum_amount(input)
      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      invoices = scope.to_a
      {
        total_amount: invoices.sum(&:total_amount).round(2),
        invoice_count: invoices.size,
        invoices: invoices.map { |invoice| invoice_summary(invoice) }
      }
    end

    def top_line_item(input)
      metric = input["metric"]
      unless SUPPORTED_METRICS.include?(metric)
        return { error: "Unsupported metric '#{metric}'. Only #{SUPPORTED_METRICS.join(", ")} is available — per-task logged hours aren't tracked yet." }
      end

      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      n = (input["n"] || 1).to_i.clamp(1, 20)
      items = InvoiceLineItem.where(invoice_id: scope.select(:id)).order(estimate_hours: :desc).limit(n).includes(invoice: :project_mapping)

      {
        metric: metric,
        results: items.map { |item| line_item_summary(item) }
      }
    end

    def average_hourly_rate(input)
      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      items = InvoiceLineItem.where(invoice_id: scope.select(:id))
      average = items.average(:hourly_rate)

      { average_hourly_rate: average ? average.to_f.round(2) : nil, line_item_count: items.count }
    end

    def count_invoices(input)
      scope, ambiguity = scoped_invoices(input)
      return ambiguity if ambiguity

      { count: scope.count }
    end

    # Applies the month range and (optional) project filter shared by every tool above.
    # Returns [scope, nil] normally, or [nil, ambiguity_hash] if `project` didn't resolve
    # to exactly one project — callers must return that hash as-is rather than guess.
    def scoped_invoices(input)
      scope = Invoice.includes(:project_mapping)
      scope = scope.where("invoices.month >= ?", input["month_from"]) if input["month_from"].present?
      scope = scope.where("invoices.month <= ?", input["month_to"]) if input["month_to"].present?

      project = input["project"]
      return [ scope, nil ] if project.blank?

      mappings = ProjectMapping.where("clickup_space_name ILIKE ?", "%#{project}%")

      case mappings.count
      when 0
        [ nil, { ambiguous: true, reason: "No project matched '#{project}'." } ]
      when 1
        [ scope.where(project_mapping: mappings.first), nil ]
      else
        [ nil, { ambiguous: true, reason: "Multiple projects matched '#{project}' — ask which one.", candidates: mappings.pluck(:clickup_space_name) } ]
      end
    end

    def invoice_summary(invoice)
      {
        name: invoice.name,
        month: invoice.month,
        project: invoice.project_mapping.clickup_space_name,
        total_amount: invoice.total_amount.to_f.round(2),
        total_estimate_hours: invoice.total_estimate_hours.to_f.round(2),
        line_item_count: invoice.invoice_line_items.size
      }
    end

    def invoice_detail(invoice)
      invoice_summary(invoice).merge(
        line_items: invoice.invoice_line_items.map do |item|
          {
            title: item.title,
            ticket: item.ticket,
            hourly_rate: item.hourly_rate&.to_f,
            estimate_hours: item.estimate_hours&.to_f,
            billable: item.billable,
            amount: item.amount.to_f.round(2)
          }
        end
      )
    end

    def line_item_summary(item)
      {
        title: item.title,
        ticket: item.ticket,
        estimate_hours: item.estimate_hours&.to_f,
        invoice_name: item.invoice.name,
        month: item.invoice.month,
        project: item.invoice.project_mapping.clickup_space_name
      }
    end
  end
end
