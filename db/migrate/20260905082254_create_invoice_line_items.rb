class CreateInvoiceLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :invoice_line_items do |t|
      t.references :invoice, null: false, foreign_key: true
      t.string :clickup_task_id
      t.string :title
      t.string :ticket
      t.decimal :estimate_hours, precision: 10, scale: 2
      t.decimal :hourly_rate, precision: 10, scale: 2
      t.boolean :billable, null: false, default: true

      t.timestamps
    end
  end
end
