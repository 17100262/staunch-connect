class ProjectMappingsController < ApplicationController
  def create
    hubstaff_project_id, hubstaff_project_name = params[:hubstaff_project_value].to_s.split("|", 2)
    folder_id = params[:clickup_folder_id]
    folder_id = nil if folder_id == InvoicesController::NO_FOLDER

    ProjectMapping.create!(
      clickup_space_id: params[:clickup_space_id],
      clickup_space_name: params[:clickup_space_name],
      clickup_folder_id: folder_id,
      clickup_folder_name: params[:clickup_folder_name],
      hubstaff_project_id: hubstaff_project_id,
      hubstaff_project_name: hubstaff_project_name,
      default_hourly_rate: params[:default_hourly_rate].presence
    )
    redirect_to invoicing_path(clickup_space_id: params[:clickup_space_id], clickup_folder_id: params[:clickup_folder_id])
  end

  def destroy
    mapping = ProjectMapping.find(params[:id])
    clickup_space_id = mapping.clickup_space_id
    clickup_folder_id = mapping.clickup_folder_id || InvoicesController::NO_FOLDER

    if mapping.destroy
      redirect_to invoicing_path(clickup_space_id: clickup_space_id, clickup_folder_id: clickup_folder_id)
    else
      redirect_to invoicing_path(clickup_space_id: clickup_space_id, clickup_folder_id: clickup_folder_id),
        alert: "Can't remap — this project has #{mapping.invoices.count} invoice(s). Delete them first."
    end
  end
end
