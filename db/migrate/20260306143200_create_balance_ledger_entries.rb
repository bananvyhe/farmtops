class CreateBalanceLedgerEntries < ActiveRecord::Migration[8.0]
  def change
    create_table :balance_ledger_entries do |t|
      t.references :user, null: false, foreign_key: true
      t.references :payment_transaction, foreign_key: true
      t.integer :kind, null: false
      t.integer :amount_cents, null: false
      t.integer :balance_after_cents, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end
  end
end
