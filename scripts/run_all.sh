#!/usr/bin/env bash
# run_all.sh - Master orchestrator for the daily news digest
# Runs all scripts in sequence, with error handling per step
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TODAY=$(date +%Y-%m-%d)
LOG_FILE="$PROJECT_DIR/outputs/run_${TODAY}.log"
export STATUS_FILE="$PROJECT_DIR/outputs/raw/${TODAY}/status.json"

mkdir -p "$PROJECT_DIR/outputs" "$PROJECT_DIR/outputs/raw/${TODAY}"

# Initialize status file
echo '{}' > "$STATUS_FILE"

echo "========================================" | tee -a "$LOG_FILE"
echo "News Digest LLM - $(date)" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"

ERRORS=0

# Helper to record step status
record_status() {
    local key="$1" status="$2" msg="${3:-}"
    python3 -c "
import json
with open('${STATUS_FILE}') as f:
    data = json.load(f)
data['$key'] = {'status': '$status', 'message': '''$msg'''}
with open('${STATUS_FILE}', 'w') as f:
    json.dump(data, f, indent=2)
"
}

# Step 0: Sync X following to Feedbin
echo "" | tee -a "$LOG_FILE"
echo "[0/6] Syncing X following list..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/00_sync_x_following.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[0/6] X sync: OK" | tee -a "$LOG_FILE"
else
    echo "[0/6] X sync: FAILED (continuing)" | tee -a "$LOG_FILE"
    record_status "x_sync" "error" "X following sync failed — new follows may not appear"
    ERRORS=$((ERRORS + 1))
fi

# Step 1: Fetch Feedbin
echo "" | tee -a "$LOG_FILE"
echo "[1/6] Fetching Feedbin..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/01_fetch_feedbin.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[1/6] Feedbin: OK" | tee -a "$LOG_FILE"
    record_status "feedbin" "ok"
else
    echo "[1/6] Feedbin: FAILED (continuing)" | tee -a "$LOG_FILE"
    record_status "feedbin" "error" "Feedbin fetch failed — RSS entries missing from digest"
    ERRORS=$((ERRORS + 1))
fi

# Step 2: Fetch HN Best
echo "" | tee -a "$LOG_FILE"
echo "[2/6] Fetching HN Best..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/02_fetch_hn_best.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[2/6] HN Best: OK" | tee -a "$LOG_FILE"
    record_status "hn" "ok"
else
    echo "[2/6] HN Best: FAILED (continuing)" | tee -a "$LOG_FILE"
    record_status "hn" "error" "Hacker News fetch failed — HN section missing"
    ERRORS=$((ERRORS + 1))
fi

# Step 3: Refresh X feeds via RSSHub
echo "" | tee -a "$LOG_FILE"
echo "[3/6] Refreshing X feeds..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/03_refresh_x_feeds.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[3/6] X feeds: OK" | tee -a "$LOG_FILE"
    record_status "x_feeds" "ok"
else
    echo "[3/6] X feeds: FAILED (continuing)" | tee -a "$LOG_FILE"
    record_status "x_feeds" "error" "X feeds fetch failed — Twitter content missing. Auth token may be expired. Refresh: browser → x.com → DevTools → Application → Cookies → auth_token, then update Railway env var."
    ERRORS=$((ERRORS + 1))
fi

# Step 4: Generate summary with Claude
echo "" | tee -a "$LOG_FILE"
echo "[4/6] Generating summary..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/04_summarize.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[4/6] Summary: OK" | tee -a "$LOG_FILE"
    record_status "summarize" "ok"
else
    echo "[4/6] Summary: FAILED" | tee -a "$LOG_FILE"
    record_status "summarize" "error" "Claude summarization failed"
    ERRORS=$((ERRORS + 1))
    echo "FATAL: Cannot continue without summary. Exiting." | tee -a "$LOG_FILE"
    exit 1
fi

# Step 4.5: Inject alerts into summary if any errors occurred
python3 << PYEOF
import json

with open("${STATUS_FILE}") as f:
    status = json.load(f)

alerts = []
for key, info in status.items():
    if info.get("status") == "error":
        alerts.append(info.get("message", f"{key} failed"))

if not alerts:
    print("[alerts] No alerts to inject")
else:
    print(f"[alerts] Injecting {len(alerts)} alert(s) into summary")

    summary_file = "${PROJECT_DIR}/outputs/summaries/${TODAY}.md"
    with open(summary_file) as f:
        summary = f.read()

    # Build alert block in Slack mrkdwn
    alert_block = "⚠️ *Pipeline Alerts*\n\n"
    for a in alerts:
        alert_block += f"- 🔴 {a}\n"
    alert_block += "\n---\n\n"

    with open(summary_file, "w") as f:
        f.write(alert_block + summary)
PYEOF

# Step 5: Post to Slack
echo "" | tee -a "$LOG_FILE"
echo "[5/6] Posting to Slack..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/05_post_slack.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[5/6] Slack: OK" | tee -a "$LOG_FILE"
else
    echo "[5/6] Slack: FAILED" | tee -a "$LOG_FILE"
    ERRORS=$((ERRORS + 1))
fi

# Step 6: Send email via Resend
echo "" | tee -a "$LOG_FILE"
echo "[6/6] Sending email via Resend..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/06_post_email.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[6/6] Email: OK" | tee -a "$LOG_FILE"
else
    echo "[6/6] Email: FAILED" | tee -a "$LOG_FILE"
    ERRORS=$((ERRORS + 1))
fi

echo "" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
if [ "$ERRORS" -eq 0 ]; then
    echo "All steps completed successfully!" | tee -a "$LOG_FILE"
else
    echo "Completed with $ERRORS error(s). Check log: $LOG_FILE" | tee -a "$LOG_FILE"
fi
echo "========================================" | tee -a "$LOG_FILE"
