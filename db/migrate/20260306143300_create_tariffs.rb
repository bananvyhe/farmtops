class CreateTariffs < ActiveRecord::Migration[8.0]
  def change
    create_table :tariffs do |t|
      t.string :name, null: false
      t.integer :monthly_price_cents, null: false, default: 0
      t.integer :hourly_rate_cents, null: false, default: 0
      t.integer :billing_period_days, null: false, default: 30
      t.boolean :active, null: false, default: true
      t.text :description

      t.timestamps
    end

    add_index :tariffs, :name, unique: true
  end
end
