module Shards
  class MembershipPresence
    def self.touch(shard:, user:)
      membership = shard.layer_memberships.find_by(user_id: user.id)
      membership&.touch_presence!
      membership
    end

    def self.prune_stale!(shard:, threshold: ShardLayerMembership::PRESENCE_TTL.ago)
      shard.layer_memberships.stale(threshold).delete_all
    end
  end
end
