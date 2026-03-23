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
    begin
      NewsCrawlSectionJob.new.perform(section.id)
    rescue StandardError => e
      warn "Skipped #{source.name} / #{section.name}: #{e.class} #{e.message}"
    end
  end
end

puts "One-shot news crawl completed."
RUBY
