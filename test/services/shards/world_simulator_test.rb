require "test_helper"

class Shards::WorldSimulatorTest < ActiveSupport::TestCase
  test "only active prime members appear in the authoritative world snapshot" do
    game = Game.create!(name: "World Game", slug: "world-game")
    owner = User.create!(
      email: "owner@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      nickname: "owner-one",
      role: :client
    )
    active_slot = Time.current.utc.wday * 24 + Time.current.utc.hour
    active_user = User.create!(
      email: "active@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      nickname: "active-one",
      role: :client,
      prime_time_zone: "UTC",
      prime_slots_utc: [active_slot]
    )
    inactive_user = User.create!(
      email: "inactive@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      nickname: "inactive-one",
      role: :client,
      prime_time_zone: "UTC",
      prime_slots_utc: []
    )

    shard = Shard.create!(
      user: owner,
      game: game,
      name: "World Game · owner-one",
      world_seed: "seed1234",
      status: :active
    )
    layer = shard.default_layer
    layer.memberships.create!(
      shard: shard,
      user: active_user,
      joined_at: Time.current,
      last_seen_at: Time.current
    )
    layer.memberships.create!(
      shard: shard,
      user: inactive_user,
      joined_at: Time.current,
      last_seen_at: Time.current
    )

    snapshot = Shards::WorldSimulator.new(shard: shard, layer: layer).call

    assert_equal "active", snapshot[:mode]
    assert_equal 1, snapshot[:active_players_count]
    assert_equal 1, snapshot[:players].size
    assert_equal active_user.nickname, snapshot[:players].first[:nickname]
    assert_equal active_slot, snapshot[:current_week_slot_utc]
    assert layer.reload.world_state.present?
    assert_equal 2, layer.world_state_version
  end
end
