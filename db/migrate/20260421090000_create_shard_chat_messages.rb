class CreateShardChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :shard_chat_messages do |t|
      t.references :shard, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :content, null: false

      t.timestamps
    end

    add_index :shard_chat_messages, [:shard_id, :created_at], name: "index_shard_chat_messages_on_shard_and_created_at"
  end
end
