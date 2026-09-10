class AddFolderToProjectMappings < ActiveRecord::Migration[8.1]
  def up
    add_column :project_mappings, :clickup_folder_id, :string
    add_column :project_mappings, :clickup_folder_name, :string

    # Backfill the one existing mapping (space-wide) with the folder it's
    # actually been used for, so its existing invoice keeps resolving once
    # ProjectMapping becomes folder-scoped instead of space-scoped.
    execute <<~SQL
      UPDATE project_mappings
      SET clickup_folder_id = '90188391025', clickup_folder_name = 'Alpha Sync'
      WHERE clickup_space_id = '19276251' AND clickup_folder_id IS NULL
    SQL
  end

  def down
    remove_column :project_mappings, :clickup_folder_id
    remove_column :project_mappings, :clickup_folder_name
  end
end
