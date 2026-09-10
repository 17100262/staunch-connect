class AddWebhookFieldsToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :webhook_id, :string
    add_column :connections, :webhook_secret, :text
  end
end
