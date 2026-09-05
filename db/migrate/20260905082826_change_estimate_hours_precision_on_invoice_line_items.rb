class ChangeEstimateHoursPrecisionOnInvoiceLineItems < ActiveRecord::Migration[8.1]
  def up
    change_column :invoice_line_items, :estimate_hours, :decimal, precision: 12, scale: 6
  end

  def down
    change_column :invoice_line_items, :estimate_hours, :decimal, precision: 10, scale: 2
  end
end
