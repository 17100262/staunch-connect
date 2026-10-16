class AddProfileFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :name, :string
    add_column :users, :job_title, :string
    add_column :users, :time_zone, :string
  end
end
