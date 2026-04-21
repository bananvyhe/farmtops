module Shards
  class RealtimeBroadcaster
    class << self
      def stream_name(shard_id)
        "shard:#{shard_id}"
      end

      def broadcast_world_snapshot(shard:, payload:)
        safe_broadcast(
          stream_name(shard.id),
          {
            type: "world_snapshot",
            payload: payload
          }
        )
      end

      def broadcast_chat_message(shard:, message:)
        safe_broadcast(
          stream_name(shard.id),
          {
            type: "chat_message",
            message: chat_message_payload(message)
          }
        )
      end

      def chat_message_payload(message)
        {
          id: message.id,
          shard_id: message.shard_id,
          user_id: message.user_id,
          nickname: message.user.nickname,
          content: message.content,
          created_at: message.created_at
        }
      end

      def chat_bootstrap_payload(shard:, limit: 50)
        messages = shard.chat_messages.includes(:user).recent_first.limit(limit).reverse
        {
          type: "chat_bootstrap",
          messages: messages.map { |message| chat_message_payload(message) }
        }
      end

      private

      def safe_broadcast(stream, payload)
        ActionCable.server.broadcast(stream, payload)
      rescue StandardError => e
        Rails.logger.error("[RealtimeBroadcaster] stream=#{stream} error=#{e.class}: #{e.message}")
        false
      end
    end
  end
end
