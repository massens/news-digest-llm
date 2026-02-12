#!/usr/bin/env bash
# 03_refresh_x_feeds.sh - Fetch X/Twitter home timeline via self-hosted RSSHub
# Uses /twitter/home_latest for a single fast request covering all followed accounts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

TODAY=$(date +%Y-%m-%d)
OUTPUT_DIR="$PROJECT_DIR/outputs/raw/$TODAY"
OUTPUT_FILE="$OUTPUT_DIR/x_feeds.txt"

mkdir -p "$OUTPUT_DIR"

echo "[x_feeds] Fetching X home timeline via RSSHub at $RSSHUB_BASE_URL..."

# Primary: home_latest gives the full chronological timeline in one request
FEED_URL="${RSSHUB_BASE_URL}/twitter/home_latest"
RESPONSE=$(curl -s --max-time 30 "$FEED_URL" 2>/dev/null || echo "FETCH_ERROR")

if [ "$RESPONSE" = "FETCH_ERROR" ] || [ -z "$RESPONSE" ] || echo "$RESPONSE" | grep -q "<title>Welcome to RSSHub"; then
    echo "[x_feeds] home_latest failed, falling back to individual accounts..."
    RESPONSE=""
fi

> "$OUTPUT_FILE"

if [ -n "$RESPONSE" ]; then
    # Parse the home timeline RSS
    echo "$RESPONSE" | python3 -c "
import sys, re, html

content = sys.stdin.read()
items = re.findall(r'<item>(.*?)</item>', content, re.DOTALL)

count = 0
for item in items:
    title_match = re.search(r'<title><!\[CDATA\[(.*?)\]\]></title>', item, re.DOTALL)
    if not title_match:
        title_match = re.search(r'<title>(.*?)</title>', item, re.DOTALL)
    title = html.unescape(title_match.group(1).strip()) if title_match else '(no title)'

    link_match = re.search(r'<link>(.*?)</link>', item)
    link = link_match.group(1).strip() if link_match else ''

    author_match = re.search(r'<author>(.*?)</author>', item)
    author = html.unescape(author_match.group(1).strip()) if author_match else ''

    pubdate_match = re.search(r'<pubDate>(.*?)</pubDate>', item)
    pubdate = pubdate_match.group(1).strip() if pubdate_match else ''

    desc_match = re.search(r'<description><!\[CDATA\[(.*?)\]\]></description>', item, re.DOTALL)
    if not desc_match:
        desc_match = re.search(r'<description>(.*?)</description>', item, re.DOTALL)
    desc = ''
    if desc_match:
        desc = re.sub('<[^>]+>', ' ', html.unescape(desc_match.group(1)))
        desc = re.sub(r'\s+', ' ', desc).strip()[:500]

    if title and title != '(no title)':
        print(f'---')
        print(f'account: @{author}')
        print(f'title: {title[:300]}')
        print(f'url: {link}')
        print(f'date: {pubdate}')
        print(f'content: {desc}')
        count += 1

print(f'---TOTAL:{count}', file=sys.stderr)
" >> "$OUTPUT_FILE" 2>/tmp/x_feeds_count.txt

    TOTAL=$(grep -o 'TOTAL:[0-9]*' /tmp/x_feeds_count.txt 2>/dev/null | cut -d: -f2 || echo "0")
    echo "[x_feeds] Home timeline: $TOTAL tweets fetched in single request"
else
    # Fallback: fetch individual key accounts
    echo "[x_feeds] Using individual account fallback..."
    X_ACCOUNTS=(
        "simonw" "levelsio" "naval" "bcherny" "rohanpaul_ai"
        "kimmonismus" "cremieuxrecueil" "steipete" "nikitabier"
        "cursor_ai" "AnthropicAI" "OpenAI" "GergelyOrosz" "sama"
    )

    SUCCESS=0
    for ACCOUNT in "${X_ACCOUNTS[@]}"; do
        FEED_URL="${RSSHUB_BASE_URL}/twitter/user/${ACCOUNT}"
        ACCT_RESPONSE=$(curl -s --max-time 15 "$FEED_URL" 2>/dev/null || echo "")
        if [ -n "$ACCT_RESPONSE" ] && ! echo "$ACCT_RESPONSE" | grep -q "<title>Welcome to RSSHub"; then
            echo "$ACCT_RESPONSE" | python3 -c "
import sys, re, html
content = sys.stdin.read()
items = re.findall(r'<item>(.*?)</item>', content, re.DOTALL)
account = '${ACCOUNT}'
for item in items[:5]:
    title_match = re.search(r'<title><!\[CDATA\[(.*?)\]\]></title>', item, re.DOTALL)
    if not title_match:
        title_match = re.search(r'<title>(.*?)</title>', item, re.DOTALL)
    title = html.unescape(title_match.group(1).strip()) if title_match else ''
    link_match = re.search(r'<link>(.*?)</link>', item)
    link = link_match.group(1).strip() if link_match else ''
    pubdate_match = re.search(r'<pubDate>(.*?)</pubDate>', item)
    pubdate = pubdate_match.group(1).strip() if pubdate_match else ''
    desc_match = re.search(r'<description><!\[CDATA\[(.*?)\]\]></description>', item, re.DOTALL)
    if not desc_match:
        desc_match = re.search(r'<description>(.*?)</description>', item, re.DOTALL)
    desc = ''
    if desc_match:
        desc = re.sub('<[^>]+>', ' ', html.unescape(desc_match.group(1)))
        desc = re.sub(r'\s+', ' ', desc).strip()[:400]
    if title:
        print(f'---')
        print(f'account: @{account}')
        print(f'title: {title[:200]}')
        print(f'url: {link}')
        print(f'date: {pubdate}')
        print(f'content: {desc}')
" >> "$OUTPUT_FILE" 2>/dev/null
            SUCCESS=$((SUCCESS + 1))
        fi
    done
    echo "[x_feeds] Fallback: $SUCCESS accounts fetched"
fi

OUTPUT_SIZE=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')
echo "[x_feeds] Done. Output: $OUTPUT_FILE ($OUTPUT_SIZE bytes)"
