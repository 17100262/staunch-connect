class AddOauthTokensToConnections < ActiveRecord::Migration[8.1]
  def change
    add_column :connections, :access_token, :text
    add_column :connections, :access_token_expires_at, :datetime
  end
end
