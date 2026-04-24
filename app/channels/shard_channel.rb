class ShardChannel < ApplicationCable::Channel
  def subscribed
    @shard = find_visible_shard
    reject unless @shard

    Shards::MembershipPresence.touch(shard: @shard, user: current_user)
    stream_from Shards::RealtimeBroadcaster.stream_name(@shard.id)
    transmit Shards::RealtimeBroadcaster.chat_bootstrap_payload(shard: @shard)
    transmit(
      type: "world_snapshot",
      payload: Shards::WorldStateBuilder.new(shard: @shard, current_user: current_user).call
    )
  end

  def tick
    return unless @shard

    Shards::MembershipPresence.touch(shard: @shard, user: current_user)
    payload = Shards::WorldStateBuilder.new(shard: @shard, current_user: current_user).call
    Shards::RealtimeBroadcaster.broadcast_world_snapshot(shard: @shard, payload: payload)
  end

  def speak(data)
    return unless @shard

    content = data["content"].to_s.strip
    return if content.blank?

    Shards::LayerAllocator.new(shard: @shard, user: current_user).call
    message = @shard.chat_messages.create!(user: current_user, content: content)
    Shards::RealtimeBroadcaster.broadcast_chat_message(shard: @shard, message: message)
  end

  private

  def find_visible_shard
    shard_id = params[:shard_id].to_i
    return nil if shard_id <= 0

    Shard.visible_to_user(current_user).find_by(id: shard_id)
  end
end
