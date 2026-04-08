class AddNicknameToUsers < ActiveRecord::Migration[8.0]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  def up
    add_column :users, :nickname, :string
    add_column :users, :nickname_change_used, :boolean, null: false, default: false
    add_index :users, :nickname, unique: true

    MigrationUser.reset_column_information
    say_with_time "Backfilling user nicknames" do
      MigrationUser.find_each do |user|
        user.update_columns(
          nickname: unique_nickname_for(user.id),
          nickname_change_used: false
        )
      end
    end

    change_column_null :users, :nickname, false
  end

  def down
    remove_index :users, :nickname
    remove_column :users, :nickname_change_used
    remove_column :users, :nickname
  end

  private

  def unique_nickname_for(seed)
    loop do
      candidate = "u_#{SecureRandom.alphanumeric(8).downcase}"
      return candidate unless MigrationUser.exists?(nickname: candidate)
    end
  end
end
