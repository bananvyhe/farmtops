#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RAILS_ENV="${RAILS_ENV:-development}"
SITES_FILE="${SITES_FILE:-sites.txt}"

cd "$ROOT_DIR"

bundle exec rails news:import_sites FILE="$SITES_FILE"

bundle exec rails runner - <<'RUBY'
puts "Running one-shot news crawl..."

NewsSource.active.find_each do |source|
  source.news_sections.active.find_each do |section|
    puts "Crawling #{source.name} / #{section.name}"
    NewsCrawlSectionJob.new.perform(section.id)
  end
end

puts "One-shot news crawl completed."
RUBY
