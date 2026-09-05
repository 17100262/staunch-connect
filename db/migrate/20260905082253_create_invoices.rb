class CreateInvoices < ActiveRecord::Migration[8.1]
  def change
    create_table :invoices do |t|
      t.references :project_mapping, null: false, foreign_key: true
      t.string :month, null: false

      t.timestamps
    end

    add_index :invoices, %i[project_mapping_id month], unique: true
  end
end
