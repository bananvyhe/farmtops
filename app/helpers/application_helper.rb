module ApplicationHelper
  def rubles(cents)
    number_to_currency(cents.to_i / 100.0, unit: "₽", separator: ",", delimiter: " ", format: "%n %u")
  end

  def remaining_days_label(user)
    return "не списывается" if user.effective_hourly_rate_cents.zero?

    "#{user.remaining_days} дн."
  end
end
