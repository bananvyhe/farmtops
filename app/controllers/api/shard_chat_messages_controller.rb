module Api
  class ShardChatMessagesController < BaseController
    before_action :ensure_authenticated!
    before_action :set_shard

    def index
      messages = @shard.chat_messages.includes(:user).recent_first.limit(50).reverse
      render json: { messages: messages.map { |message| message_payload(message) } }
    end

    def create
      content = params[:content].to_s.strip
      return render_error("Message is empty", status: :unprocessable_entity) if content.blank?

      Shards::LayerAllocator.new(shard: @shard, user: current_user).call
      message = @shard.chat_messages.create!(user: current_user, content: content)
      Shards::RealtimeBroadcaster.broadcast_chat_message(shard: @shard, message: message)

      render json: { message: message_payload(message) }, status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    def set_shard
      @shard = Shard.visible_to_user(current_user).find_by(id: params[:shard_id])
      render_error("Shard not found", status: :not_found) if @shard.blank?
    end

    def message_payload(message)
      Shards::RealtimeBroadcaster.chat_message_payload(message)
    end
  end
end
