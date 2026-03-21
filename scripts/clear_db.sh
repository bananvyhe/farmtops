#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAILS_ENV="${RAILS_ENV:-development}"
CONFIRM="${CONFIRM_DB_CLEAR:-}"

if [ "$RAILS_ENV" = "production" ]; then
  echo "Refusing to clear production database."
  exit 1
fi

if [ "$CONFIRM" != "YES" ]; then
  echo "Set CONFIRM_DB_CLEAR=YES to clear the $RAILS_ENV database."
  exit 1
fi

cd "$ROOT_DIR"

bundle exec rails runner - <<'RUBY'
connection = ActiveRecord::Base.connection
tables = connection.tables - %w[schema_migrations ar_internal_metadata]

if tables.empty?
  puts "No tables to clear."
  exit 0
end

quoted_tables = tables.map { |table| connection.quote_table_name(table) }
sql = "TRUNCATE TABLE #{quoted_tables.join(', ')} RESTART IDENTITY CASCADE"

puts "Clearing tables: #{tables.sort.join(', ')}"
connection.execute(sql)
puts "Database cleared."
RUBY
