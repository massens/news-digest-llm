#!/usr/bin/env bash
# 02b_fetch_telegram.sh - Fetch messages from Telegram groups (last 7 days for context)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

echo "[telegram] Fetching Telegram group messages..."

# Check session exists
if [ ! -f "$SCRIPT_DIR/telegram.session" ]; then
    echo "[telegram] ERROR: No session file. Run: python3 scripts/fetch_telegram.py --auth"
    exit 1
fi

# Export credentials for Python script
export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_GROUPS

python3 "$SCRIPT_DIR/fetch_telegram.py"
