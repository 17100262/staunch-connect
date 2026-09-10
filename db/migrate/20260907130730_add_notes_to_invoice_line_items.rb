class AddNotesToInvoiceLineItems < ActiveRecord::Migration[8.1]
  def change
    add_column :invoice_line_items, :notes, :text
  end
end
