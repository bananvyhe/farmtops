module Shards
  class LayerAllocator
    Result = Struct.new(:layer, :membership, keyword_init: true)

    def initialize(shard:, user:, desired_layer_id: nil)
      @shard = shard
      @user = user
      @desired_layer_id = desired_layer_id
    end

    def call
      membership = nil
      layer = nil

      Shard.transaction do
        @shard.lock!
        layer = @shard.default_layer

        membership = @shard.layer_memberships.find_or_initialize_by(user_id: @user.id)
        membership.shard_layer = layer
        membership.joined_at ||= Time.current
        membership.last_seen_at = Time.current
        membership.save!

        if layer.campaign_started_at.blank?
          layer.update!(
            campaign_started_at: Time.current,
            campaign_target_players: [layer.memberships.count, 2].max
          )
        end
      end

      Result.new(layer:, membership:)
    end
  end
end
