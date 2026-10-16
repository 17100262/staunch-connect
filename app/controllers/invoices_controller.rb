class InvoicesController < ApplicationController
  RETRYABLE_ERRORS = [
    ClickupClient::AuthenticationError, ClickupClient::RequestError,
    HubstaffClient::AuthenticationError, HubstaffClient::RequestError
  ].freeze

  TICKET_NUMBER_FIELD_NAMES = [ "harper ticket number", "ticket number", "htn" ].freeze
  NO_FOLDER = "none"
  SETUP_STEP_TEMPLATES = { 1 => "invoices/setup/step1", 2 => "invoices/setup/step2", 3 => "invoices/setup/step3" }.freeze

  before_action :require_connections, only: %i[new draft create]

  def index
    @invoices = Invoice.includes(:project_mapping, :invoice_line_items).order(created_at: :desc)
  end

  # Setup modal (Project -> Lists -> Check the setup). Rendered inside the
  # `modal` Turbo Frame; a direct (non-frame) visit shows the list with the
  # modal opened over it.
  def new
    unless turbo_frame_request?
      @modal_src = request.fullpath
      @invoices = Invoice.includes(:project_mapping, :invoice_line_items).order(created_at: :desc)
      return render :index
    end

    load_setup
    @step = params[:step].to_i.clamp(1, 3)
    @step = 1 if params[:step].blank?
    @step = 1 if @step > 1 && @setup["clickup_folder_id"].blank?
    @step = 2 if @step > 2 && @setup["list_ids"].empty?

    case @step
    when 1 then load_projects
    when 2 then load_lists
    else load_check
    end

    persist_hubstaff_tokens!
    render SETUP_STEP_TEMPLATES.fetch(@step)
  rescue *RETRYABLE_ERRORS => e
    persist_hubstaff_tokens!
    @error = e.message
    render "invoices/setup/error"
  end

  # Review: reconciliation of the chosen lists. Side-effect free; the setup
  # travels in the query string and is only persisted by #create.
  def draft
    load_setup

    if @setup["clickup_space_id"].blank? || @setup["clickup_folder_id"].blank? || @setup["list_ids"].empty?
      return redirect_to invoices_path, alert: "Choose a project and at least one list first."
    end

    @mapping = find_mapping(@setup["clickup_folder_id"], @setup["clickup_space_id"])
    @hub_id, @hub_name = hubstaff_selection(@setup["hubstaff_project_value"], @mapping)
    @rate = rate_from(@setup["rate"], @mapping)
    @month = valid_month(@setup["month"])
    @month_options = last_12_months
    month_start = Date.strptime(@month, "%Y-%m")

    top_level_tasks, subtasks_by_parent = partition_tasks(@setup["list_ids"].flat_map { |list_id| clickup_client.tasks(list_id) })
    @line_items = top_level_tasks.map { |task| build_line_item(task, subtasks_by_parent[task["id"]] || []) }
    @total_estimate_hours = @line_items.sum { |item| item[:estimate_hours] || 0 }
    @total_amount = @total_estimate_hours * @rate
    @project_name = @setup["clickup_folder_name"].presence || @mapping&.clickup_folder_name.presence || @setup["clickup_space_name"]

    if @hub_id.present?
      organization_id = hubstaff_client.organizations.first["id"]
      activities = hubstaff_client.daily_activities(
        organization_id: organization_id,
        project_id: @hub_id,
        date_from: month_start.to_s,
        date_to: month_start.end_of_month.to_s
      )
      @total_logged_hours = activities.sum { |activity| activity["tracked"] } / 3600.0
    end

    persist_hubstaff_tokens!
  rescue *RETRYABLE_ERRORS => e
    persist_hubstaff_tokens!
    redirect_to invoices_path, alert: e.message
  end

  def create
    load_setup
    list_ids = @setup["list_ids"]

    if @setup["clickup_space_id"].blank? || @setup["clickup_folder_id"].blank? || list_ids.empty?
      return redirect_to invoices_path, alert: "Choose a project and at least one list first."
    end

    month = valid_month(@setup["month"])
    mapping = find_mapping(@setup["clickup_folder_id"], @setup["clickup_space_id"]) || new_mapping_from_setup
    hub_id, hub_name = hubstaff_selection(@setup["hubstaff_project_value"], mapping)
    rate = rate_from(@setup["rate"], mapping)

    mapping.hubstaff_project_id = hub_id
    mapping.hubstaff_project_name = hub_name
    mapping.default_hourly_rate ||= rate if rate.positive?
    mapping.save!

    if (existing = Invoice.find_by(project_mapping: mapping, month: month))
      return redirect_to invoice_path(existing), notice: "An invoice for #{Date.strptime(month, '%Y-%m').strftime('%B %Y')} already exists, so it was opened instead."
    end

    invoice = build_invoice(mapping, month, list_ids, rate)

    persist_hubstaff_tokens!
    redirect_to invoice_path(invoice), notice: "Invoice saved."
  rescue *RETRYABLE_ERRORS => e
    persist_hubstaff_tokens!
    redirect_to invoices_path, alert: e.message
  end

  def show
    @invoice = Invoice.find(params[:id])
  end

  def update
    @invoice = Invoice.find(params[:id])
    @invoice.update!(invoice_params)
    redirect_to invoice_path(@invoice), notice: "Changes saved."
  end

  def destroy
    Invoice.find(params[:id]).destroy
    redirect_to invoices_path, notice: "Invoice deleted."
  end

  def export
    invoice = Invoice.find(params[:id])
    include_subtasks = params[:include_subtasks] != "0"
    include_off = params[:include_off] == "1"

    items = invoice.invoice_line_items.order(:id)
    items = items.where(billable: true) unless include_off

    package = Axlsx::Package.new
    wrap_style = package.workbook.styles.add_style(alignment: { wrap_text: true, vertical: :top })

    package.workbook.add_worksheet(name: "Invoice") do |sheet|
      header = [ "Task", "Ticket", "Hours", "Rate", "Amount" ]
      header << "Billed" if include_off
      header << "Notes" if include_subtasks
      sheet.add_row header

      items.each do |item|
        row = [ item.title, item.ticket, item.estimate_hours, item.hourly_rate, item.amount ]
        row << (item.billable ? "Yes" : "No") if include_off
        row << item.notes if include_subtasks
        sheet.add_row row, style: (include_subtasks ? Array.new(row.size - 1) + [ wrap_style ] : nil)
      end

      sheet.add_row []
      sheet.add_row Array.new(header.index("Rate")) + [ "Total", invoice.total_amount ]
      sheet.column_widths(*Array.new(header.size - 1) + [ include_subtasks ? 50 : nil ])
    end

    base = params[:file_name].to_s.strip.delete_suffix(".xlsx").presence || "invoice-#{invoice.name}-#{invoice.month}"
    filename = base.parameterize(separator: "-") + ".xlsx"
    send_data package.to_stream.read, filename: filename, type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  end

  private

  def invoice_params
    params.require(:invoice).permit(:name, invoice_line_items_attributes: %i[id title estimate_hours hourly_rate billable notes])
  end

  # A folder maps to one project uniquely; the "No Folder" bucket (folderless
  # lists sitting directly in a Space) falls back to one shared mapping per
  # Space, matching how ProjectMapping's uniqueness validations are scoped.
  def find_mapping(folder_id, space_id)
    if folder_id == NO_FOLDER
      ProjectMapping.find_by(clickup_space_id: space_id, clickup_folder_id: nil)
    else
      ProjectMapping.find_by(clickup_folder_id: folder_id)
    end
  end

  def lists_for_folder(space_id, folder_id)
    if folder_id == NO_FOLDER
      clickup_client.lists(space_id)
    else
      clickup_client.folders(space_id).find { |f| f["id"] == folder_id }&.fetch("lists", []) || []
    end
  end

  def build_invoice(mapping, month, list_ids, rate = nil)
    top_level_tasks, subtasks_by_parent = partition_tasks(list_ids.flat_map { |list_id| clickup_client.tasks(list_id) })
    name = mapping.clickup_folder_name.presence || mapping.clickup_space_name.presence || mapping.clickup_space_id

    Invoice.create!(project_mapping: mapping, month: month, name: name) do |invoice|
      top_level_tasks.each do |task|
        invoice.invoice_line_items.build(
          clickup_task_id: task["id"],
          title: titled_with_ticket_number(task),
          ticket: task["custom_id"].presence || task["id"],
          estimate_hours: task["time_estimate"] ? task["time_estimate"] / 3_600_000.0 : 0,
          hourly_rate: rate.presence || mapping.default_hourly_rate,
          billable: true,
          notes: format_subtask_notes(subtasks_by_parent[task["id"]] || [])
        )
      end
    end
  end

  # ClickUp returns a task's subtasks as flat siblings in the same list, marked
  # with a "parent" field pointing back to the parent task's id (nil for top-level
  # tasks) — this splits that flat array back into parent/child groups.
  def partition_tasks(tasks)
    subtasks_by_parent = tasks.select { |t| t["parent"] }.group_by { |t| t["parent"] }
    top_level_tasks = tasks.reject { |t| t["parent"] }
    [ top_level_tasks, subtasks_by_parent ]
  end

  def format_subtask_notes(subtasks)
    return nil if subtasks.empty?

    subtasks.map { |t| "• #{titled_with_ticket_number(t)}" }.join("\n")
  end

  # Merges a ClickUp custom field like "HTN" ("Harper Ticket Number") into the
  # start of the task's title, wherever it's set — some spaces/clients name the
  # field differently for the same concept. Leaves the title untouched if no
  # matching field has a value. Distinct from the "Ticket" column, which shows
  # ClickUp's own custom_id/id.
  def titled_with_ticket_number(task)
    field = (task["custom_fields"] || []).find do |f|
      TICKET_NUMBER_FIELD_NAMES.include?(f["name"].to_s.downcase) && f["value"].to_s.present?
    end

    field ? "#{field['value']} - #{task['name']}" : task["name"]
  end

  SETUP_SCALARS = %w[clickup_space_id clickup_space_name clickup_folder_id clickup_folder_name month rate hubstaff_project_value mode].freeze

  def load_setup
    @setup = params.permit(*SETUP_SCALARS, list_ids: []).to_h
    @setup["list_ids"] = Array(@setup["list_ids"]).reject(&:blank?)
  end

  def load_projects
    @spaces = clickup_client.spaces(team_id)
    @space = @spaces.find { |s| s["id"] == @setup["clickup_space_id"] } || @spaces.first
    return unless @space

    @setup["clickup_space_id"] = @space["id"]
    @setup["clickup_space_name"] = @space["name"]
    @folders = clickup_client.folders(@space["id"])
    @folderless_lists = clickup_client.lists(@space["id"])
  end

  def load_lists
    @lists = lists_for_folder(@setup["clickup_space_id"], @setup["clickup_folder_id"])
  end

  def load_check
    @mapping = find_mapping(@setup["clickup_folder_id"], @setup["clickup_space_id"])
    @hub_options = hubstaff_project_options
    project_name = @setup["clickup_folder_name"].presence || @mapping&.clickup_folder_name
    @matched_hub = @hub_options.find { |o| normalize_name(o[:name].split(" / ").last) == normalize_name(project_name) }

    if @setup["hubstaff_project_value"].blank?
      @setup["hubstaff_project_value"] =
        if @mapping&.hubstaff_project_id.present?
          "#{@mapping.hubstaff_project_id}|#{@mapping.hubstaff_project_name}"
        elsif @matched_hub
          "#{@matched_hub[:id]}|#{@matched_hub[:name]}"
        else
          "none"
        end
    end

    @hub_id, @hub_name = hubstaff_selection(@setup["hubstaff_project_value"], @mapping)
    @hub_state = if @hub_id.blank? then "none"
    elsif @matched_hub && @matched_hub[:id].to_s == @hub_id.to_s then "matched"
    else "chosen"
    end
    @rate = rate_from(@setup["rate"], @mapping)
    @month = valid_month(@setup["month"])
    @month_options = last_12_months
    @list_names = lists_for_folder(@setup["clickup_space_id"], @setup["clickup_folder_id"])
      .select { |l| @setup["list_ids"].include?(l["id"]) }.map { |l| l["name"] }
  end

  # "id|name" from the setup form, "none" for "Do not compare", otherwise the
  # project saved on the mapping.
  def hubstaff_selection(value, mapping)
    return [ nil, nil ] if value == "none"
    return value.split("|", 2) if value.present?

    [ mapping&.hubstaff_project_id.presence, mapping&.hubstaff_project_name ]
  end

  def rate_from(value, mapping)
    parsed = BigDecimal(value.to_s.strip) if value.to_s.strip.match?(/\A\d+(\.\d+)?\z/)
    return parsed if parsed&.positive?

    mapping&.default_hourly_rate || BigDecimal("0")
  end

  def valid_month(value)
    value.to_s.match?(/\A\d{4}-\d{2}\z/) ? value : Date.current.strftime("%Y-%m")
  end

  def normalize_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9]/, "")
  end

  def new_mapping_from_setup
    folder_id = @setup["clickup_folder_id"]
    ProjectMapping.new(
      clickup_space_id: @setup["clickup_space_id"],
      clickup_space_name: @setup["clickup_space_name"],
      clickup_folder_id: (folder_id == NO_FOLDER ? nil : folder_id),
      clickup_folder_name: @setup["clickup_folder_name"]
    )
  end

  def require_connections
    @clickup_connection = Connection.find_by(source: "clickup")
    @hubstaff_connection = Connection.find_by(source: "hubstaff")

    return if @clickup_connection&.connected? && @hubstaff_connection&.connected?

    if turbo_frame_request?
      @error = "Invoicing needs both ClickUp and Hubstaff connected. Check the connections in Settings."
      render "invoices/setup/error"
    else
      render :not_connected
    end
  end

  def clickup_client
    @clickup_client ||= ClickupClient.new(@clickup_connection.credential)
  end

  def hubstaff_client
    @hubstaff_client ||= HubstaffClient.new(
      @hubstaff_connection.credential,
      access_token: @hubstaff_connection.access_token,
      access_token_expires_at: @hubstaff_connection.access_token_expires_at
    )
  end

  def persist_hubstaff_tokens!
    return unless @hubstaff_client

    @hubstaff_connection.update!(
      credential: @hubstaff_client.refresh_token,
      access_token: @hubstaff_client.access_token,
      access_token_expires_at: @hubstaff_client.access_token_expires_at
    )
  end

  def team_id
    clickup_client.teams.first["id"]
  end

  def hubstaff_project_options
    hubstaff_client.organizations.flat_map do |org|
      hubstaff_client.projects(org["id"]).map { |project| { id: project["id"], name: "#{org['name']} / #{project['name']}" } }
    end
  end

  def last_12_months
    (0..11).map do |i|
      date = i.months.ago.beginning_of_month
      [ date.strftime("%Y-%m"), date.strftime("%B %Y") ]
    end
  end

  def build_line_item(task, subtasks = [])
    {
      title: titled_with_ticket_number(task),
      ticket: task["custom_id"].presence || task["id"],
      estimate_hours: task["time_estimate"] ? task["time_estimate"] / 3_600_000.0 : nil,
      notes: format_subtask_notes(subtasks)
    }
  end
end
