class ProjectMappingsController < ApplicationController
  def create
    hubstaff_project_id, hubstaff_project_name = params[:hubstaff_project_value].to_s.split("|", 2)

    ProjectMapping.create!(
      clickup_space_id: params[:clickup_space_id],
      clickup_space_name: params[:clickup_space_name],
      hubstaff_project_id: hubstaff_project_id,
      hubstaff_project_name: hubstaff_project_name,
      default_hourly_rate: params[:default_hourly_rate].presence
    )
    redirect_to invoicing_path(clickup_space_id: params[:clickup_space_id])
  end

  def destroy
    mapping = ProjectMapping.find(params[:id])
    clickup_space_id = mapping.clickup_space_id
    mapping.destroy
    redirect_to invoicing_path(clickup_space_id: clickup_space_id)
  end
end
