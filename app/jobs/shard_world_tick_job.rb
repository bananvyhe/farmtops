class ShardWorldTickJob
  include Sidekiq::Job

  def perform
    Shard.active.includes(layers: { memberships: :user }).find_each do |shard|
      shard.layers.active.find_each do |layer|
        Shards::WorldSimulator.new(shard:, layer:).call
      rescue StandardError => e
        Rails.logger.error("[ShardWorldTickJob] shard=#{shard.id} layer=#{layer.id} error=#{e.class}: #{e.message}")
      end
    end
  end
end
