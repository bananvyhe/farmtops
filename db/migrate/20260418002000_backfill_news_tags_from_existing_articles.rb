class BackfillNewsTagsFromExistingArticles < ActiveRecord::Migration[8.0]
  def up
    return unless table_exists?(:news_articles) && table_exists?(:news_tags) && table_exists?(:news_article_tags)

    NewsArticle.reset_column_information
    NewsTag.reset_column_information
    NewsArticleTag.reset_column_information

    NewsArticle.find_each do |article|
      article.replace_news_tags!(article.class.extract_tag_names_from_payload(article))
    end
  end

  def down
    # No-op. The join rows are derived data and can be regenerated from article HTML.
  end
end
