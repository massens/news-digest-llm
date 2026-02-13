#!/usr/bin/env bash
# 04_summarize.sh - Use Claude CLI to generate summary from raw data
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

TODAY=$(date +%Y-%m-%d)
RAW_DIR="$PROJECT_DIR/outputs/raw/$TODAY"
SUMMARY_DIR="$PROJECT_DIR/outputs/summaries"
SUMMARY_FILE="$SUMMARY_DIR/${TODAY}.md"
PROMPT_FILE="$PROJECT_DIR/prompts/summarize.md"
TEMP_PROMPT="/tmp/news-digest-prompt-${TODAY}.txt"

mkdir -p "$SUMMARY_DIR"

echo "[summarize] Generating summary for $TODAY..."

# Check that raw data exists
if [ ! -d "$RAW_DIR" ]; then
    echo "[summarize] ERROR: No raw data found at $RAW_DIR. Run fetch scripts first."
    exit 1
fi

# Build prompt file (avoids shell argument length limits)
cat "$PROMPT_FILE" > "$TEMP_PROMPT"

cat >> "$TEMP_PROMPT" <<EOF

---

Today's date: $TODAY

Here is all the raw news data. Analyze it and produce the daily briefing:

EOF

if [ -f "$RAW_DIR/feedbin.txt" ]; then
    FEEDBIN_SIZE=$(wc -c < "$RAW_DIR/feedbin.txt" | tr -d ' ')
    echo "[summarize] Including feedbin.txt ($FEEDBIN_SIZE bytes)"
    echo "=== FEEDBIN RSS ENTRIES ===" >> "$TEMP_PROMPT"
    cat "$RAW_DIR/feedbin.txt" >> "$TEMP_PROMPT"
    echo "" >> "$TEMP_PROMPT"
fi

if [ -f "$RAW_DIR/hn_best.txt" ]; then
    HN_SIZE=$(wc -c < "$RAW_DIR/hn_best.txt" | tr -d ' ')
    echo "[summarize] Including hn_best.txt ($HN_SIZE bytes)"
    echo "=== HACKER NEWS BEST STORIES ===" >> "$TEMP_PROMPT"
    cat "$RAW_DIR/hn_best.txt" >> "$TEMP_PROMPT"
    echo "" >> "$TEMP_PROMPT"
fi

if [ -f "$RAW_DIR/x_feeds.txt" ]; then
    X_SIZE=$(wc -c < "$RAW_DIR/x_feeds.txt" | tr -d ' ')
    echo "[summarize] Including x_feeds.txt ($X_SIZE bytes)"
    echo "=== X/TWITTER FEEDS ===" >> "$TEMP_PROMPT"
    cat "$RAW_DIR/x_feeds.txt" >> "$TEMP_PROMPT"
    echo "" >> "$TEMP_PROMPT"
fi

if [ -f "$RAW_DIR/telegram.txt" ]; then
    TG_SIZE=$(wc -c < "$RAW_DIR/telegram.txt" | tr -d ' ')
    echo "[summarize] Including telegram.txt ($TG_SIZE bytes)"
    echo "=== TELEGRAM GROUP MESSAGES (AIrtesans - last 7 days for context) ===" >> "$TEMP_PROMPT"
    cat "$RAW_DIR/telegram.txt" >> "$TEMP_PROMPT"
    echo "" >> "$TEMP_PROMPT"
fi

PROMPT_SIZE=$(wc -c < "$TEMP_PROMPT" | tr -d ' ')
echo "[summarize] Total prompt: $PROMPT_SIZE bytes"
echo "[summarize] Running Claude CLI (this may take 60-120 seconds)..."

# Pipe prompt via stdin to avoid shell argument length limits
SUMMARY=$(cat "$TEMP_PROMPT" | $CLAUDE_CMD -p --output-format text --no-session-persistence 2>/dev/null)

if [ -z "$SUMMARY" ]; then
    echo "[summarize] ERROR: Claude returned empty response"
    rm -f "$TEMP_PROMPT"
    exit 1
fi

# Save summary to file
echo "$SUMMARY" > "$SUMMARY_FILE"

# Cleanup
rm -f "$TEMP_PROMPT"

echo "[summarize] Done. Summary saved to $SUMMARY_FILE ($(wc -c < "$SUMMARY_FILE" | tr -d ' ') bytes)"
