class CreatePaymentTransactions < ActiveRecord::Migration[8.0]
  def change
    create_table :payment_transactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :provider, null: false, default: "yoomoney"
      t.string :payment_method, null: false, default: "bank_card"
      t.string :label, null: false
      t.integer :status, null: false, default: 0
      t.integer :requested_amount_cents, null: false
      t.integer :credited_amount_cents, null: false, default: 0
      t.integer :provider_net_amount_cents, null: false, default: 0
      t.string :provider_operation_id
      t.datetime :paid_at
      t.jsonb :provider_payload, null: false, default: {}

      t.timestamps
    end

    add_index :payment_transactions, :label, unique: true
    add_index :payment_transactions, :provider_operation_id
  end
end
