class InvoicesController < ApplicationController
  RETRYABLE_ERRORS = [
    ClickupClient::AuthenticationError, ClickupClient::RequestError,
    HubstaffClient::AuthenticationError, HubstaffClient::RequestError
  ].freeze

  before_action :require_connections, only: %i[new draft]

  def new
    @clickup_space_id = params[:clickup_space_id]

    if @clickup_space_id.blank?
      @spaces = clickup_client.spaces(team_id)
      template = :project_picker
    else
      @mapping = ProjectMapping.find_by(clickup_space_id: @clickup_space_id)

      if @mapping.nil?
        @clickup_space_name = params[:clickup_space_name]
        @hubstaff_project_options = hubstaff_project_options
        template = :project_mapping
      else
        @folders = clickup_client.folders(@clickup_space_id)
        @folderless_lists = clickup_client.lists(@clickup_space_id)
        template = :list_picker
      end
    end

    persist_hubstaff_tokens!
    render template
  rescue *RETRYABLE_ERRORS => e
    persist_hubstaff_tokens!
    redirect_to connections_path, alert: e.message
  end

  def draft
    @clickup_space_id = params[:clickup_space_id]
    @list_ids = Array(params[:list_ids]).reject(&:blank?)

    if @clickup_space_id.blank? || @list_ids.empty?
      return redirect_to invoicing_path, alert: "Select a project and at least one list first."
    end

    @mapping = ProjectMapping.find_by(clickup_space_id: @clickup_space_id)

    if @mapping.nil?
      return redirect_to invoicing_path(clickup_space_id: @clickup_space_id), alert: "Map this project to a Hubstaff project first."
    end

    @month = params[:month].presence || Date.current.strftime("%Y-%m")
    @month_options = last_12_months
    month_start = Date.strptime(@month, "%Y-%m")
    month_end = month_start.end_of_month

    @line_items = @list_ids.flat_map { |list_id| clickup_client.tasks(list_id) }.map { |task| build_line_item(task) }
    @total_estimate_hours = @line_items.sum { |item| item[:estimate_hours] || 0 }

    organization_id = hubstaff_client.organizations.first["id"]
    activities = hubstaff_client.daily_activities(
      organization_id: organization_id,
      project_id: @mapping.hubstaff_project_id,
      date_from: month_start.to_s,
      date_to: month_end.to_s
    )
    @total_logged_hours = activities.sum { |activity| activity["tracked"] } / 3600.0

    persist_hubstaff_tokens!
  rescue *RETRYABLE_ERRORS => e
    persist_hubstaff_tokens!
    redirect_to connections_path, alert: e.message
  end

  private

  def require_connections
    @clickup_connection = Connection.find_by(source: "clickup")
    @hubstaff_connection = Connection.find_by(source: "hubstaff")

    render :not_connected unless @clickup_connection&.connected? && @hubstaff_connection&.connected?
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

  def build_line_item(task)
    {
      title: task["name"],
      ticket: task["custom_id"].presence || task["id"],
      estimate_hours: task["time_estimate"] ? task["time_estimate"] / 3_600_000.0 : nil
    }
  end
end
