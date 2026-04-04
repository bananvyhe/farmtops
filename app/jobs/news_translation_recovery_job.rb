class NewsTranslationRecoveryJob
  include Sidekiq::Job

  def perform(crawl_run_id = nil)
    News::Translation::Recovery.new.call(crawl_run_id)
  end
end
