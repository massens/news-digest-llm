# Telegram Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Telegram as a data source using Telethon — backfill 6 months of private group history, then integrate into the daily pipeline.

**Architecture:** A single Python script (`fetch_telegram.py`) with three modes: `--auth` for session setup, default for daily 24h fetch, `--backfill N` for historical dump. A thin bash wrapper (`02b_fetch_telegram.sh`) plugs it into the existing pipeline. Telethon is the only new dependency.

**Tech Stack:** Python 3 + Telethon, bash wrapper, credentials.env for secrets

---

### Task 1: Setup — requirements.txt, .gitignore, credentials

**Files:**
- Create: `requirements.txt`
- Modify: `.gitignore`
- Modify: `credentials.env`

**Step 1: Create requirements.txt**

```
telethon
```

**Step 2: Install telethon**

Run: `pip3 install telethon`
Expected: Successfully installed telethon

**Step 3: Add session file to .gitignore**

Add `*.session` to `.gitignore` (after the existing `*.swp` line).

**Step 4: Add Telegram credentials to credentials.env**

Append to `credentials.env`:
```bash
# Telegram
TELEGRAM_API_ID="38852243"
TELEGRAM_API_HASH="84813f4c27244e0c082761351560b53d"
TELEGRAM_GROUPS=""
```

Leave `TELEGRAM_GROUPS` empty for now — we'll discover available groups during auth.

**Step 5: Commit**

```bash
git add requirements.txt .gitignore
git commit -m "chore: add telethon dependency and gitignore session files"
```

Note: Do NOT commit credentials.env (it's gitignored).

---

### Task 2: Write fetch_telegram.py — auth mode

**Files:**
- Create: `scripts/fetch_telegram.py`

**Step 1: Write the script with --auth mode**

```python
#!/usr/bin/env python3
"""Fetch messages from Telegram groups using Telethon.

Usage:
    python3 fetch_telegram.py --auth          # One-time phone auth
    python3 fetch_telegram.py                  # Daily fetch (last 24h)
    python3 fetch_telegram.py --backfill 180   # Backfill last N days
    python3 fetch_telegram.py --list-groups    # List all groups/channels you're in
"""

import argparse
import asyncio
import json
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from telethon import TelegramClient
from telethon.tl.types import Channel, Chat, User

SCRIPT_DIR = Path(__file__).parent.resolve()
PROJECT_DIR = SCRIPT_DIR.parent
SESSION_FILE = str(SCRIPT_DIR / "telegram")


def get_config():
    """Read Telegram config from environment variables."""
    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")
    groups_str = os.environ.get("TELEGRAM_GROUPS", "")

    if not api_id or not api_hash:
        print("[telegram] ERROR: TELEGRAM_API_ID and TELEGRAM_API_HASH must be set")
        print("[telegram] Source credentials.env or export them before running")
        sys.exit(1)

    groups = [g.strip() for g in groups_str.split(",") if g.strip()]
    return int(api_id), api_hash, groups


def make_client(api_id, api_hash):
    return TelegramClient(SESSION_FILE, api_id, api_hash)


async def do_auth(client):
    """Interactive first-time authentication."""
    print("[telegram] Starting authentication...")
    print("[telegram] You will be asked for your phone number and a verification code.")
    await client.start()
    me = await client.get_me()
    print(f"[telegram] Authenticated as: {me.first_name} (@{me.username})")
    print(f"[telegram] Session saved to: {SESSION_FILE}.session")


async def list_groups(client):
    """List all groups and channels the user is part of."""
    await client.start()
    print("[telegram] Groups and channels you're in:\n")
    async for dialog in client.iter_dialogs():
        entity = dialog.entity
        if isinstance(entity, (Channel, Chat)):
            kind = "channel" if isinstance(entity, Channel) else "group"
            username = getattr(entity, 'username', None)
            name_str = f"{dialog.name}"
            if username:
                name_str += f" (@{username})"
            print(f"  [{kind}] {name_str} — ID: {entity.id}")


async def fetch_daily(client, groups, output_file):
    """Fetch last 24h of messages from configured groups."""
    await client.start()
    since = datetime.now(timezone.utc) - timedelta(hours=24)

    messages_out = []
    for group_name in groups:
        try:
            entity = await client.get_entity(group_name)
        except Exception as e:
            print(f"[telegram] WARNING: Could not find group '{group_name}': {e}")
            continue

        group_title = getattr(entity, 'title', group_name)
        count = 0
        async for msg in client.iter_messages(entity, offset_date=since, reverse=True):
            if not msg.text:
                continue
            sender = await msg.get_sender()
            sender_name = ""
            if sender:
                if isinstance(sender, User):
                    sender_name = sender.username or sender.first_name or str(sender.id)
                else:
                    sender_name = getattr(sender, 'title', str(sender.id))

            text = msg.text[:500] if msg.text else ""
            messages_out.append(
                f"---\n"
                f"title: {group_title}\n"
                f"date: {msg.date.isoformat()}\n"
                f"author: {sender_name}\n"
                f"content: {text}"
            )
            count += 1
        print(f"[telegram] {group_title}: {count} messages (last 24h)")

    output_file.parent.mkdir(parents=True, exist_ok=True)
    output_file.write_text("\n".join(messages_out))
    print(f"[telegram] Done. {len(messages_out)} messages saved to {output_file}")


async def backfill(client, groups, days, output_dir):
    """Backfill last N days of messages as JSON for analysis."""
    await client.start()
    since = datetime.now(timezone.utc) - timedelta(days=days)
    output_dir.mkdir(parents=True, exist_ok=True)

    if not groups:
        print("[telegram] No groups configured in TELEGRAM_GROUPS.")
        print("[telegram] Run with --list-groups to see available groups, then set TELEGRAM_GROUPS.")
        sys.exit(1)

    for group_name in groups:
        try:
            entity = await client.get_entity(group_name)
        except Exception as e:
            print(f"[telegram] WARNING: Could not find group '{group_name}': {e}")
            continue

        group_title = getattr(entity, 'title', group_name)
        safe_name = "".join(c if c.isalnum() or c in "-_ " else "" for c in group_title).strip().replace(" ", "_").lower()
        out_file = output_dir / f"{safe_name}.json"

        messages = []
        count = 0
        async for msg in client.iter_messages(entity, offset_date=since, reverse=True):
            sender = await msg.get_sender()
            sender_name = ""
            sender_username = ""
            sender_id = None
            if sender:
                if isinstance(sender, User):
                    sender_name = sender.first_name or ""
                    sender_username = sender.username or ""
                    sender_id = sender.id
                else:
                    sender_name = getattr(sender, 'title', "")
                    sender_id = sender.id

            messages.append({
                "id": msg.id,
                "date": msg.date.isoformat(),
                "sender_id": sender_id,
                "sender_name": sender_name,
                "sender_username": sender_username,
                "text": msg.text or "",
                "reply_to_msg_id": msg.reply_to.reply_to_msg_id if msg.reply_to else None,
                "views": msg.views,
                "forwards": msg.forwards,
            })
            count += 1
            if count % 500 == 0:
                print(f"[telegram] {group_title}: {count} messages so far...")

        out_file.write_text(json.dumps(messages, indent=2, ensure_ascii=False))
        print(f"[telegram] {group_title}: {count} messages saved to {out_file}")


def main():
    parser = argparse.ArgumentParser(description="Fetch Telegram group messages")
    parser.add_argument("--auth", action="store_true", help="Run interactive authentication")
    parser.add_argument("--list-groups", action="store_true", help="List all groups/channels")
    parser.add_argument("--backfill", type=int, metavar="DAYS", help="Backfill last N days as JSON")
    args = parser.parse_args()

    api_id, api_hash, groups = get_config()
    client = make_client(api_id, api_hash)

    if args.auth:
        asyncio.run(do_auth(client))
    elif args.list_groups:
        asyncio.run(list_groups(client))
    elif args.backfill:
        output_dir = PROJECT_DIR / "outputs" / "raw" / "telegram_backfill"
        asyncio.run(backfill(client, groups, args.backfill, output_dir))
    else:
        if not groups:
            print("[telegram] ERROR: TELEGRAM_GROUPS is empty. Set it in credentials.env.")
            sys.exit(1)
        today = datetime.now().strftime("%Y-%m-%d")
        output_file = PROJECT_DIR / "outputs" / "raw" / today / "telegram.txt"
        asyncio.run(fetch_daily(client, groups, output_file))


if __name__ == "__main__":
    main()
```

**Step 2: Make it executable and test auth**

Run: `chmod +x scripts/fetch_telegram.py`

Then source credentials and run auth interactively:
```bash
source credentials.env && python3 scripts/fetch_telegram.py --auth
```
Expected: Prompts for phone number, then verification code. Creates `scripts/telegram.session`.

**Step 3: List groups to discover available ones**

```bash
source credentials.env && python3 scripts/fetch_telegram.py --list-groups
```
Expected: Prints all groups/channels with names and IDs. User picks which ones to add to TELEGRAM_GROUPS.

**Step 4: Commit**

```bash
git add scripts/fetch_telegram.py
git commit -m "feat: add Telegram fetch script with auth, daily, and backfill modes"
```

---

### Task 3: Test backfill — pull 6 months of history

**Depends on:** Task 2 (auth must be complete, TELEGRAM_GROUPS must be set)

**Step 1: Set TELEGRAM_GROUPS in credentials.env**

After running `--list-groups`, add the chosen group names/IDs to credentials.env.

**Step 2: Run backfill**

```bash
source credentials.env && python3 scripts/fetch_telegram.py --backfill 180
```

Expected: Creates `outputs/raw/telegram_backfill/<group_name>.json` per group. Progress printed every 500 messages. May take a few minutes depending on volume.

**Step 3: Check the output**

```bash
ls -lh outputs/raw/telegram_backfill/
python3 -c "import json; d=json.load(open('outputs/raw/telegram_backfill/<group_name>.json')); print(f'{len(d)} messages, first: {d[0][\"date\"]}, last: {d[-1][\"date\"]}')"
```

Expected: JSON files with message data spanning ~6 months.

---

### Task 4: Analyze backfill — AI coding topics

**Depends on:** Task 3

**Step 1: Explore the data with Claude**

Feed the backfill JSON to Claude CLI and ask for topic analysis:

```bash
cat outputs/raw/telegram_backfill/*.json | claude -p "Analyze these Telegram group messages. Focus on AI coding topics. Identify: (1) the top 10-15 recurring themes/topics discussed, (2) which topics are most actively discussed (by message count and engagement), (3) key links/resources shared, (4) whether this content would add value to a daily AI/tech news digest that already covers Feedbin RSS, Hacker News, and X/Twitter. Be specific with examples from the messages." --output-format text
```

Review output to decide next steps for daily integration.

---

### Task 5: Pipeline integration — bash wrapper + run_all.sh

**Files:**
- Create: `scripts/02b_fetch_telegram.sh`
- Modify: `scripts/run_all.sh`

**Step 1: Create the bash wrapper**

```bash
#!/usr/bin/env bash
# 02b_fetch_telegram.sh - Fetch messages from Telegram groups (last 24h)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

echo "[telegram] Fetching Telegram group messages..."

# Check session exists
if [ ! -f "$SCRIPT_DIR/telegram.session" ]; then
    echo "[telegram] ERROR: No session file. Run: source credentials.env && python3 scripts/fetch_telegram.py --auth"
    exit 1
fi

# Export credentials for Python script
export TELEGRAM_API_ID TELEGRAM_API_HASH TELEGRAM_GROUPS

python3 "$SCRIPT_DIR/fetch_telegram.py"
```

**Step 2: Make it executable**

```bash
chmod +x scripts/02b_fetch_telegram.sh
```

**Step 3: Add Telegram step to run_all.sh**

Insert after the HN Best step (after line 69), before Step 3 (X feeds). Update step numbering from `[x/6]` to `[x/7]` for all subsequent steps. Add:

```bash
# Step 2b: Fetch Telegram groups
echo "" | tee -a "$LOG_FILE"
echo "[2b/7] Fetching Telegram..." | tee -a "$LOG_FILE"
if bash "$SCRIPT_DIR/02b_fetch_telegram.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[2b/7] Telegram: OK" | tee -a "$LOG_FILE"
    record_status "telegram" "ok"
else
    echo "[2b/7] Telegram: FAILED (continuing)" | tee -a "$LOG_FILE"
    record_status "telegram" "error" "Telegram fetch failed — Telegram messages missing from digest. Session may be expired: run python3 scripts/fetch_telegram.py --auth"
    ERRORS=$((ERRORS + 1))
fi
```

**Step 4: Add telegram.txt to 04_summarize.sh**

Insert after the x_feeds.txt block (after line 61 of `04_summarize.sh`):

```bash
if [ -f "$RAW_DIR/telegram.txt" ]; then
    TG_SIZE=$(wc -c < "$RAW_DIR/telegram.txt" | tr -d ' ')
    echo "[summarize] Including telegram.txt ($TG_SIZE bytes)"
    echo "=== TELEGRAM GROUP MESSAGES ===" >> "$TEMP_PROMPT"
    cat "$RAW_DIR/telegram.txt" >> "$TEMP_PROMPT"
    echo "" >> "$TEMP_PROMPT"
fi
```

**Step 5: Test daily fetch standalone**

```bash
source credentials.env && bash scripts/02b_fetch_telegram.sh
ls -lh outputs/raw/$(date +%Y-%m-%d)/telegram.txt
```

Expected: Creates telegram.txt with today's messages.

**Step 6: Commit**

```bash
git add scripts/02b_fetch_telegram.sh scripts/run_all.sh scripts/04_summarize.sh
git commit -m "feat: integrate Telegram into daily news digest pipeline"
```

---

### Task 6: Update summarize prompt (if analysis shows value)

**Depends on:** Task 4 analysis results

**Files:**
- Modify: `prompts/summarize.md`

If the backfill analysis shows Telegram adds valuable AI coding content not covered by other sources, add a new section to the prompt. For example, add after the "Hacker News Highlights" priority item:

```
5. **Telegram Group Insights**: Notable discussions, tips, or resources shared in private AI/engineering Telegram groups
```

And update the output structure to include a Telegram section. Only do this if the analysis shows it adds value beyond noise.
