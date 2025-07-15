class AddPushSubscriptions < ActiveRecord::Migration[8.1]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint
      t.string :p256dh_key
      t.string :auth_key
      t.string :user_agent
      t.timestamps
      
      t.index [:user_id, :endpoint], unique: true
      t.index :endpoint
      t.index :user_agent
      t.index ["endpoint", "p256dh_key", "auth_key"]
    end
  end
end