# Telegram Integration Design

## Goal

Add Telegram as a data source to the news-digest-llm pipeline using Telethon. Pull messages from 1-3 private industry/tech groups. Initial task: backfill 6 months of history to explore AI coding topics being discussed.

## Credentials

- `TELEGRAM_API_ID=38852243`
- `TELEGRAM_API_HASH=84813f4c27244e0c082761351560b53d`
- `TELEGRAM_GROUPS=<comma-separated group names or IDs>`
- Session file: `scripts/telegram.session` (gitignored, created via one-time phone auth)

## New Files

### `scripts/fetch_telegram.py`

Telethon-based script with three modes:

- `--auth` — Interactive first-time session creation (phone + code + optional 2FA)
- (no flags) — Daily fetch: last 24h from configured groups → `outputs/raw/YYYY-MM-DD/telegram.txt`
- `--backfill N` — Pull last N days → `outputs/raw/telegram_backfill/<group_name>.json`

### `scripts/02b_fetch_telegram.sh`

Thin bash wrapper for pipeline integration:
- Sources `credentials.env`
- Runs `python3 scripts/fetch_telegram.py`
- Updates `status.json`

### `requirements.txt`

Single dependency: `telethon`

## Data Formats

### Daily pipeline output (`telegram.txt`)

Matches existing source format:
```
---
title: [Group Name]
date: 2026-02-12T14:30:00+00:00
author: sender_username
content: message text (500 char max)
```

### Backfill output (`telegram_backfill/<group>.json`)

Richer JSON for analysis:
```json
[{
  "id": 12345,
  "date": "2026-02-12T14:30:00+00:00",
  "sender_id": 123,
  "sender_name": "John",
  "sender_username": "johndoe",
  "text": "full message text",
  "reply_to_msg_id": null,
  "views": 42,
  "forwards": 3
}]
```

## Pipeline Integration

`run_all.sh` gets one new line after `02_fetch_hn_best.sh`:
```bash
bash scripts/02b_fetch_telegram.sh
```

## Error Handling

- No session file → "Run --auth first"
- Expired session → Telethon auto-reconnects; if truly expired, error in status.json
- Group not found → Skip with warning, continue others
- Rate limits → Telethon handles flood waits automatically
- Pipeline failure → status.json error entry, alert injected into daily summary

## Analysis Plan (Post-Backfill)

Primary question: What AI coding topics are being discussed that Marc should care about?

Analysis approach:
1. Dump 6 months via `--backfill 180`
2. Review data volume and shape
3. Use Claude to identify dominant AI/coding themes
4. Determine if Telegram highlights should become a section in the daily digest
