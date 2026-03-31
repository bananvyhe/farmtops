#!/bin/zsh
set -euo pipefail

if [ "${1:-}" = "" ]; then
  echo "Usage: $0 ARTICLE_ID [source|translated]"
  exit 1
fi

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [ -f "$ROOT_DIR/.env" ]; then
  set -a
  . "$ROOT_DIR/.env"
  set +a
fi

export NEWS_TRANSLATOR_BASE_URL="${NEWS_TRANSLATOR_BASE_URL:-http://127.0.0.1:19191}"
export NEWS_GAME_ID_BASE_URL="${NEWS_GAME_ID_BASE_URL:-http://127.0.0.1:19192}"

if [ "${NEWS_TRANSLATOR_BASE_URL:-}" = "http://127.0.0.1:19191" ] && ! curl -fsS --max-time 1 http://127.0.0.1:19191/health >/dev/null 2>&1; then
  if curl -fsS --max-time 1 http://127.0.0.1:8008/health >/dev/null 2>&1; then
    export NEWS_TRANSLATOR_BASE_URL="http://127.0.0.1:8008"
  fi
fi

ARTICLE_ID="$1"
MODE="${2:-source}"
echo "Using Rails-resolved game-id config (shell env is optional)"

BASE_URL="$(bundle exec rails runner 'puts News::GameIdentification::Client.new.instance_variable_get(:@base_url)')"
TOKEN_STATE="$(bundle exec rails runner 'puts News::GameIdentification::Client.new.instance_variable_get(:@token).present? ? "present" : "absent"')"
BASE_URL="${BASE_URL//$'\r'/}"
TOKEN_STATE="${TOKEN_STATE//$'\r'/}"

echo "Rails resolved game-id base URL: ${BASE_URL}"
echo "Rails resolved game-id token: ${TOKEN_STATE}"

if ! curl -fsS --max-time 3 "${BASE_URL}/health" >/dev/null 2>&1; then
  echo "Game-id health check failed at ${BASE_URL}/health"
  echo "The tunnel/service is not reachable from this machine."
  exit 1
fi

bundle exec rails runner - <<RUBY
article = NewsArticle.includes(:news_article_game).find(${ARTICLE_ID})
body_text =
  case "${MODE}"
  when "translated"
    article.body_text.to_s
  else
    article.source_body_text.presence || article.body_text.to_s
  end

client = News::GameIdentification::Client.new
result = client.identify_game(article_id: article.id, body_text: body_text, request_id: SecureRandom.uuid)

puts JSON.pretty_generate(result.to_h)
RUBY
