class AddPrimeCycleFieldsToUsers < ActiveRecord::Migration[8.0]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  REFERENCE_LOCAL_MONDAY = Date.new(2026, 1, 5)
  REFERENCE_UTC_MONDAY = Time.utc(2026, 1, 5, 0, 0, 0)

  def up
    add_column :users, :prime_cycle_days, :integer, null: false, default: 7
    add_column :users, :prime_cycle_slots_local, :integer, array: true, null: false, default: []
    add_column :users, :prime_cycle_anchor_on, :date, null: false, default: REFERENCE_LOCAL_MONDAY
    add_index :users, :prime_cycle_slots_local, using: :gin

    say_with_time "Backfilling prime cycle fields from weekly UTC slots" do
      MigrationUser.reset_column_information

      MigrationUser.find_each do |user|
        time_zone = Time.find_zone(user.prime_time_zone.presence || "UTC") || Time.find_zone!("UTC")
        cycle_slots = Array(user.prime_slots_utc).filter_map do |slot|
          slot_value = slot.to_i
          next if slot_value.negative? || slot_value >= 168

          utc_time = REFERENCE_UTC_MONDAY + slot_value.hours
          local_time = utc_time.in_time_zone(time_zone)
          local_day_index = (local_time.wday + 6) % 7
          (local_day_index * 24) + local_time.hour
        end.uniq.sort

        user.update_columns(
          prime_cycle_days: 7,
          prime_cycle_slots_local: cycle_slots,
          prime_cycle_anchor_on: REFERENCE_LOCAL_MONDAY
        )
      end
    end
  end

  def down
    remove_index :users, :prime_cycle_slots_local
    remove_column :users, :prime_cycle_anchor_on
    remove_column :users, :prime_cycle_slots_local
    remove_column :users, :prime_cycle_days
  end
end
