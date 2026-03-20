class AddTariffToUsers < ActiveRecord::Migration[8.0]
  def change
    add_reference :users, :tariff, foreign_key: true
  end
end
