#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAILS_ENV="${RAILS_ENV:-development}"
CONFIRM="${CONFIRM_NEWS_CLEAR:-}"

if [ "$RAILS_ENV" = "production" ]; then
  echo "Refusing to clear production database."
  exit 1
fi

if [ "$CONFIRM" != "YES" ]; then
  echo "Set CONFIRM_NEWS_CLEAR=YES to clear news tables in the $RAILS_ENV database."
  exit 1
fi

cd "$ROOT_DIR"

bundle exec rails runner - <<'RUBY'
connection = ActiveRecord::Base.connection
tables = %w[news_articles news_crawl_runs news_sections news_sources]
existing_tables = tables & connection.tables

if existing_tables.empty?
  puts "No news tables to clear."
  exit 0
end

quoted_tables = existing_tables.map { |table| connection.quote_table_name(table) }
sql = "TRUNCATE TABLE #{quoted_tables.join(', ')} RESTART IDENTITY CASCADE"

puts "Clearing news tables: #{existing_tables.sort.join(', ')}"
connection.execute(sql)
puts "News database section cleared."
RUBY
