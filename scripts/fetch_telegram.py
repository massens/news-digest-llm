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


async def resolve_entity(client, group_name):
    """Resolve a group name or ID to a Telethon entity.

    Handles numeric IDs by searching dialogs (required for channels/supergroups
    since Telethon needs the access_hash which is only available from dialogs).
    """
    # Try numeric ID: search dialogs for matching entity
    try:
        target_id = int(group_name)
        async for dialog in client.iter_dialogs():
            if dialog.entity.id == target_id:
                return dialog.entity
        raise ValueError(f"No dialog found with ID {target_id}")
    except ValueError:
        pass

    # Otherwise treat as username/invite link
    return await client.get_entity(group_name)


def load_credentials_env():
    """Load credentials.env file, setting any vars not already in environment."""
    creds_file = PROJECT_DIR / "credentials.env"
    if not creds_file.exists():
        return
    for line in creds_file.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key not in os.environ:
            os.environ[key] = value


def get_config():
    """Read Telegram config from environment variables (with credentials.env fallback)."""
    load_credentials_env()

    api_id = os.environ.get("TELEGRAM_API_ID")
    api_hash = os.environ.get("TELEGRAM_API_HASH")
    groups_str = os.environ.get("TELEGRAM_GROUPS", "")

    if not api_id or not api_hash:
        print("[telegram] ERROR: TELEGRAM_API_ID and TELEGRAM_API_HASH must be set")
        print("[telegram] Add them to credentials.env or export them before running")
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
            entity = await resolve_entity(client, group_name)
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
            entity = await resolve_entity(client, group_name)
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
