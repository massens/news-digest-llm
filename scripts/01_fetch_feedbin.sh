#!/usr/bin/env bash
# 01_fetch_feedbin.sh - Fetch unread entries from Feedbin API (last 24h)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

TODAY=$(date +%Y-%m-%d)
YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
OUTPUT_DIR="$PROJECT_DIR/outputs/raw/$TODAY"
OUTPUT_FILE="$OUTPUT_DIR/feedbin.txt"

mkdir -p "$OUTPUT_DIR"

echo "[feedbin] Fetching unread entries since ${YESTERDAY}T00:00:00Z..."

# Fetch entries page by page
PAGE=1
TOTAL=0
> "$OUTPUT_FILE"

while true; do
    RESPONSE=$(curl -s -u "${FEEDBIN_EMAIL}:${FEEDBIN_PASSWORD}" \
        "https://api.feedbin.com/v2/entries.json?since=${YESTERDAY}T00:00:00.000000Z&per_page=100&page=${PAGE}&read=false")

    # Check if response is valid JSON array
    COUNT=$(echo "$RESPONSE" | python3 -c "import json,sys; entries=json.load(sys.stdin); print(len(entries))" 2>/dev/null || echo "0")

    if [ "$COUNT" = "0" ]; then
        break
    fi

    # Extract title, URL, content summary, and date for each entry
    echo "$RESPONSE" | python3 -c "
import json, sys, html, re

entries = json.load(sys.stdin)
for e in entries:
    title = e.get('title') or '(no title)'
    url = e.get('url') or ''
    published = (e.get('published') or '')[:16]
    author = e.get('author') or ''
    feed_id = e.get('feed_id', '')

    # Strip HTML from content for summary
    content = e.get('content') or e.get('summary') or ''
    content = re.sub('<[^>]+>', ' ', content)
    content = html.unescape(content)
    content = re.sub(r'\s+', ' ', content).strip()[:500]

    print(f'---')
    print(f'title: {title}')
    print(f'url: {url}')
    print(f'date: {published}')
    print(f'author: {author}')
    print(f'feed_id: {feed_id}')
    print(f'content: {content}')
" >> "$OUTPUT_FILE"

    TOTAL=$((TOTAL + COUNT))
    echo "[feedbin] Page $PAGE: $COUNT entries (total: $TOTAL)"

    if [ "$COUNT" -lt 100 ]; then
        break
    fi

    PAGE=$((PAGE + 1))

    # Safety: max 20 pages (2000 entries)
    if [ "$PAGE" -gt 20 ]; then
        echo "[feedbin] Reached max pages, stopping"
        break
    fi
done

echo "[feedbin] Done. $TOTAL entries saved to $OUTPUT_FILE"
