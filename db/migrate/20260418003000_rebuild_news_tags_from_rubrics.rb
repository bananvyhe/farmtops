class RebuildNewsTagsFromRubrics < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Rebuilding news tags from article headers" do
      NewsArticleTag.delete_all
      NewsTag.delete_all

      NewsArticle.find_each do |article|
        tag_names = NewsArticle.extract_tag_names_from_payload(article)
        article.replace_news_tags!(tag_names) if tag_names.present?
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
