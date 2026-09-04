class CreateProjectMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :project_mappings do |t|
      t.string :clickup_space_id
      t.string :clickup_space_name
      t.string :hubstaff_project_id
      t.string :hubstaff_project_name

      t.timestamps
    end
  end
end
