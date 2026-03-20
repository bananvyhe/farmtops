require "test_helper"

class News::SchedulerTest < ActiveSupport::TestCase
  test "uses four-hour cron by default" do
    assert_equal "0 */4 * * *", News::Scheduler.cron_expression
  end
end
