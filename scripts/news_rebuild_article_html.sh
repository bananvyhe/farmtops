#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARTICLE_ID="${1:-}"

if [ -z "$ARTICLE_ID" ]; then
  echo "Usage: $0 ARTICLE_ID" >&2
  exit 1
fi

cd "$ROOT_DIR"
bundle exec rake "news:translation:rebuild_html[${ARTICLE_ID}]"
