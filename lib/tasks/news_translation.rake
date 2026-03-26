namespace :news do
  namespace :translation do
    desc "Recover the translation queue after deploy or a translator outage"
    task recover: :environment do
      result = News::Translation::Recovery.new.call

      puts "Cleared stale lock: #{result[:cleared_lock]}"
      puts "Reset recent failed articles: #{result[:reset_recent_failed]}"
      puts "Enqueued translation job: #{result[:enqueued]}"
    end
  end
end
