class AddDefaultHourlyRateToProjectMappings < ActiveRecord::Migration[8.1]
  def change
    add_column :project_mappings, :default_hourly_rate, :decimal, precision: 10, scale: 2
  end
end
