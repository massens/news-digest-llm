#!/usr/bin/env bash
# 02_fetch_hn_best.sh - Fetch top stories from Hacker News /best
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

TODAY=$(date +%Y-%m-%d)
OUTPUT_DIR="$PROJECT_DIR/outputs/raw/$TODAY"
OUTPUT_FILE="$OUTPUT_DIR/hn_best.txt"

mkdir -p "$OUTPUT_DIR"

echo "[hn_best] Fetching Hacker News best stories..."

# Use HN API: get best story IDs, then fetch top 30
BEST_IDS=$(curl -s "https://hacker-news.firebaseio.com/v0/beststories.json" | python3 -c "
import json, sys
ids = json.load(sys.stdin)
print(' '.join(str(i) for i in ids[:30]))
")

> "$OUTPUT_FILE"
COUNT=0

for ID in $BEST_IDS; do
    ITEM=$(curl -s "https://hacker-news.firebaseio.com/v0/item/${ID}.json")

    echo "$ITEM" | python3 -c "
import json, sys
item = json.load(sys.stdin)
if item and item.get('type') == 'story':
    title = item.get('title', '(no title)')
    url = item.get('url', f\"https://news.ycombinator.com/item?id={item.get('id','')}\")
    score = item.get('score', 0)
    comments = item.get('descendants', 0)
    by = item.get('by', '')
    hn_url = f\"https://news.ycombinator.com/item?id={item.get('id','')}\"
    print(f'---')
    print(f'title: {title}')
    print(f'url: {url}')
    print(f'hn_url: {hn_url}')
    print(f'score: {score}')
    print(f'comments: {comments}')
    print(f'by: {by}')
" >> "$OUTPUT_FILE" 2>/dev/null

    COUNT=$((COUNT + 1))
done

echo "[hn_best] Done. $COUNT stories saved to $OUTPUT_FILE"
