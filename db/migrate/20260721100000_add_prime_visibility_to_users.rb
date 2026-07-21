class AddPrimeVisibilityToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :show_in_prime_search, :boolean, null: false, default: true
    add_index :users, :show_in_prime_search
  end
end
