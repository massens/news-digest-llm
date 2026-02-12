#!/usr/bin/env bash
# 05_post_slack.sh - Post the daily summary to Slack #news-digest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

TODAY=$(date +%Y-%m-%d)
SUMMARY_FILE="$PROJECT_DIR/outputs/summaries/${TODAY}.md"

echo "[slack] Posting summary to Slack ${SLACK_CHANNEL}..."

if [ ! -f "$SUMMARY_FILE" ]; then
    echo "[slack] ERROR: No summary found at $SUMMARY_FILE. Run summarize script first."
    exit 1
fi

CHAR_COUNT=$(wc -c < "$SUMMARY_FILE" | tr -d ' ')
echo "[slack] Summary is $CHAR_COUNT characters"

# Function to post a message to Slack using a temp JSON file (avoids shell escaping issues)
post_to_slack() {
    local text_file="$1"
    local json_file="/tmp/news-digest-slack-payload.json"

    # Build JSON payload using Python (handles all escaping correctly)
    python3 -c "
import json, sys

with open('${text_file}', 'r') as f:
    text = f.read()

payload = {
    'channel': '${SLACK_CHANNEL}',
    'text': text,
    'unfurl_links': False,
    'unfurl_media': False
}

with open('${json_file}', 'w') as f:
    json.dump(payload, f)
"

    RESPONSE=$(curl -s -X POST "https://slack.com/api/chat.postMessage" \
        -H "Authorization: Bearer ${SLACK_BOT_TOKEN}" \
        -H "Content-Type: application/json" \
        -d @"$json_file")

    rm -f "$json_file"

    OK=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('ok', False))" 2>/dev/null || echo "False")

    if [ "$OK" = "True" ]; then
        echo "[slack] Message posted successfully"
    else
        ERROR=$(echo "$RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin).get('error', 'unknown'))" 2>/dev/null || echo "unknown")
        echo "[slack] ERROR: Failed to post: $ERROR"
        echo "[slack] Response: $RESPONSE"
        return 1
    fi
}

# If summary is under 39000 chars, post as single message
if [ "$CHAR_COUNT" -lt 39000 ]; then
    post_to_slack "$SUMMARY_FILE"
else
    # Split into chunks using Python
    echo "[slack] Summary exceeds limit, splitting into parts..."

    python3 -c "
import sys

with open('${SUMMARY_FILE}', 'r') as f:
    content = f.read()

# Split at section boundaries (lines starting with *)
sections = content.split('\n*')
parts = []
current = ''

for i, section in enumerate(sections):
    if i > 0:
        section = '*' + section
    if len(current) + len(section) > 35000:
        if current:
            parts.append(current)
        current = section
    else:
        current += '\n' + section if current else section

if current:
    parts.append(current)

for i, part in enumerate(parts):
    filename = f'/tmp/news-digest-slack-part-{i}.txt'
    with open(filename, 'w') as f:
        f.write(part)
    print(filename)
" | while read -r part_file; do
        PART_NUM=$((${PART_NUM:-0} + 1))
        echo "[slack] Posting part $PART_NUM..."
        post_to_slack "$part_file"
        rm -f "$part_file"
        sleep 1
    done
fi

echo "[slack] Done."
