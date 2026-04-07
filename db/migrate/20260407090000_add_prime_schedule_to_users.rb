class AddPrimeScheduleToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :prime_time_zone, :string, null: false, default: "UTC"
    add_column :users, :prime_slots_utc, :integer, array: true, null: false, default: []
    add_index :users, :prime_slots_utc, using: :gin
  end
end
