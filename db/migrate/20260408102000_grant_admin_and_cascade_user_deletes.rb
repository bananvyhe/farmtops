class GrantAdminAndCascadeUserDeletes < ActiveRecord::Migration[8.0]
  def up
    remove_foreign_key :balance_ledger_entries, :users
    add_foreign_key :balance_ledger_entries, :users, on_delete: :cascade

    remove_foreign_key :news_article_reads, :users
    add_foreign_key :news_article_reads, :users, on_delete: :cascade

    remove_foreign_key :news_game_bookmarks, :users
    add_foreign_key :news_game_bookmarks, :users, on_delete: :cascade

    remove_foreign_key :payment_transactions, :users
    add_foreign_key :payment_transactions, :users, on_delete: :cascade

    remove_foreign_key :balance_ledger_entries, :payment_transactions
    add_foreign_key :balance_ledger_entries, :payment_transactions, on_delete: :cascade

    remove_foreign_key :shards, :users
    add_foreign_key :shards, :users, on_delete: :cascade

    user = User.find_by(email: "loadonden@yahoo.com")
    return unless user

    user.update_columns(role: User.roles[:admin], active: true, updated_at: Time.current)
  end

  def down
    remove_foreign_key :balance_ledger_entries, :users
    add_foreign_key :balance_ledger_entries, :users

    remove_foreign_key :news_article_reads, :users
    add_foreign_key :news_article_reads, :users

    remove_foreign_key :news_game_bookmarks, :users
    add_foreign_key :news_game_bookmarks, :users

    remove_foreign_key :payment_transactions, :users
    add_foreign_key :payment_transactions, :users

    remove_foreign_key :balance_ledger_entries, :payment_transactions
    add_foreign_key :balance_ledger_entries, :payment_transactions

    remove_foreign_key :shards, :users
    add_foreign_key :shards, :users
  end
end
