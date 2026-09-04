class CreateConnections < ActiveRecord::Migration[8.1]
  def change
    create_table :connections do |t|
      t.string :source
      t.text :credential
      t.string :status
      t.string :last_error
      t.datetime :last_used_at

      t.timestamps
    end
  end
end
