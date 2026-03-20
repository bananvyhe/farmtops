class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest, null: false
      t.integer :role, null: false, default: 2
      t.integer :balance_cents, null: false, default: 0
      t.integer :hourly_rate_cents, null: false, default: 0
      t.boolean :active, null: false, default: true
      t.string :external_id
      t.jsonb :import_metadata, null: false, default: {}
      t.datetime :last_hourly_charge_at

      t.timestamps
    end

    add_index :users, :email, unique: true
    add_index :users, :external_id
  end
end
