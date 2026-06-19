require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "apply_world_xp_bank transfers banked xp and levels up on threshold" do
    user = User.create!(
      email: "xp@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      nickname: "xp-ranger",
      role: :client,
      world_level: 1,
      world_xp_total: 0,
      world_xp_bank: 0
    )

    user.update_columns(world_xp_bank: 5_000)

    gained = user.apply_world_xp_bank!
    user.reload

    assert_equal 5_000, gained
    assert_equal 5_000, user.world_xp_total
    assert_equal 0, user.world_xp_bank
    assert_equal 3, user.world_level
    assert_equal 4_000, user.world_xp_to_next_level
  end

  test "prime_cycle_active_at? evaluates stored cycle fields against the current time" do
    user = User.create!(
      email: "prime-cycle-check@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      nickname: "prime-cycle-check",
      role: :client,
      active: true,
      prime_time_zone: "UTC",
      prime_cycle_days: 3,
      prime_cycle_anchor_on: "2026-01-05",
      prime_cycle_slots_local: [0, 25, 50]
    )

    travel_to Time.zone.parse("2026-01-06 01:00:00 UTC") do
      assert user.prime_cycle_active_at?(Time.current)
    end

    travel_to Time.zone.parse("2026-01-06 02:00:00 UTC") do
      assert_not user.prime_cycle_active_at?(Time.current)
    end
  end
end
