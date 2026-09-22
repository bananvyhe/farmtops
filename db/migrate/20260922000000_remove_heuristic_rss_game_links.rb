class RemoveHeuristicRssGameLinks < ActiveRecord::Migration[8.0]
  def up
    # RSS category names were previously treated as certain game matches.
    # Remove those synthetic relations so the articles go through the neural
    # identifier on the next recovery run.
    execute <<~SQL
      DELETE FROM news_article_games
      WHERE model = 'rss'
    SQL
  end

  def down
    # The old RSS links cannot be reconstructed safely.
  end
end
