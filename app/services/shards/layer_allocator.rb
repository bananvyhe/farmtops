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
        @shard.layers.load

        layer = if @desired_layer_id.present?
          selected = @shard.layers.find_by(id: @desired_layer_id)
          raise ActiveRecord::RecordNotFound, "Layer not found" unless selected
          raise StandardError, "Layer is full" if selected.full? && selected.memberships.where(user_id: @user.id).blank?
          selected
        else
          select_layer
        end

        membership = @shard.layer_memberships.find_or_initialize_by(user_id: @user.id)
        membership.shard_layer = layer
        membership.joined_at ||= Time.current
        membership.last_seen_at = Time.current
        membership.save!
      end

      Result.new(layer:, membership:)
    end

    private

    def select_layer
      @shard.layers.order(:layer_index).detect { |layer| !layer.full? } || @shard.layers.create!(layer_index: next_layer_index)
    end

    def next_layer_index
      (@shard.layers.maximum(:layer_index) || 0) + 1
    end
  end
end
