#!/usr/bin/env bash
# 06_post_email.sh - Send the daily summary as an HTML email via Resend
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"

TODAY=$(date +%Y-%m-%d)
SUMMARY_FILE="$PROJECT_DIR/outputs/summaries/${TODAY}.md"

echo "[email] Sending summary via Resend to ${EMAIL_TO}..."

if [ ! -f "$SUMMARY_FILE" ]; then
    echo "[email] ERROR: No summary found at $SUMMARY_FILE. Run summarize script first."
    exit 1
fi

# Convert Slack mrkdwn to HTML and send via Resend
python3 << PYEOF
import json, re, subprocess, sys, html as html_mod

TODAY = "${TODAY}"

with open("${SUMMARY_FILE}", "r") as f:
    mrkdwn = f.read()

def mrkdwn_to_html(text):
    lines = text.split("\n")
    html_lines = []
    item_count = 0

    for line in lines:
        stripped = line.strip()

        if not stripped:
            continue

        # Convert Slack links <url|text> to placeholder before escaping
        def replace_link(m):
            url = m.group(1)
            text = m.group(2)
            return f'LNKS{url}LNKM{text}LNKE'

        processed = re.sub(r'<(https?://[^|>]+)\|([^>]+)>', replace_link, stripped)

        # Escape HTML
        processed = html_mod.escape(processed)

        # Restore links
        def restore_link(m):
            url = m.group(1)
            text = m.group(2)
            return f'<a href="{url}" style="color:#000;text-decoration:underline;text-underline-offset:2px">{text}</a>'
        processed = re.sub(r'LNKS(.*?)LNKM(.*?)LNKE', restore_link, processed)

        # Convert *bold* to <b>
        processed = re.sub(r'\*([^*]+)\*', r'<b>\1</b>', processed)

        # Horizontal rule (alert separator)
        if stripped == "---":
            html_lines.append('<tr><td style="border-bottom:1px solid #e5e5e5;padding:4px 0"></td></tr>')
            continue

        # Alert header
        if "Pipeline Alerts" in processed:
            title = processed.replace("<b>","").replace("</b>","")
            html_lines.append(f'<tr><td style="padding:8px;background:#fff3cd;font-size:13px;font-weight:bold;color:#856404">{title}</td></tr>')
            item_count = 0
            continue

        # Alert items (red circle emoji)
        if "🔴" in processed and processed.startswith("- "):
            content = processed[2:]
            html_lines.append(f'<tr><td style="padding:4px 8px;background:#fff3cd;font-size:12px;color:#856404">{content}</td></tr>')
            continue

        # Main title line
        if processed.startswith('<b>Daily News Digest'):
            html_lines.append(f'<tr><td style="padding:16px 0 4px;font-size:13px;color:#828282">{processed.replace("<b>","").replace("</b>","")}</td></tr>')
            continue

        # Section headers
        if re.match(r'^<b>[^<]+</b>$', processed):
            title = processed.replace("<b>","").replace("</b>","")
            html_lines.append(f'<tr><td style="padding:18px 0 6px"><b style="font-size:13px;color:#000">{title}</b></td></tr>')
            item_count = 0
            continue

        # Bullet items
        if processed.startswith("- "):
            item_count += 1
            content = processed[2:]
            # Split on em-dash to separate title link from description
            parts = content.split(' — ', 1)
            if len(parts) == 2:
                title_part = parts[0]
                desc_part = parts[1]
                # Check for HN points
                pts_match = re.search(r'\((\d+ pts)[^)]*\)', title_part)
                pts_html = ""
                if pts_match:
                    pts_html = f' <span style="color:#828282;font-size:11px">({pts_match.group(1)})</span>'
                    title_part = title_part[:pts_match.start()].strip()
                html_lines.append(f'<tr><td style="padding:4px 0;font-size:13px;line-height:1.4">{item_count}. {title_part}{pts_html}<br><span style="color:#828282;font-size:12px">{desc_part}</span></td></tr>')
            else:
                html_lines.append(f'<tr><td style="padding:4px 0;font-size:13px;line-height:1.4">{item_count}. {content}</td></tr>')
            continue

        # Regular text
        html_lines.append(f'<tr><td style="padding:2px 0;font-size:13px;color:#828282">{processed}</td></tr>')

    return "\n".join(html_lines)

body_html = mrkdwn_to_html(mrkdwn)

full_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
</head>
<body style="margin:0;padding:0;background:#f6f6ef;font-family:Verdana,Geneva,sans-serif">
<table cellpadding="0" cellspacing="0" style="width:100%;background:#f6f6ef;padding:8px">
<tr><td style="background:#ff6600;padding:4px 8px">
<b style="color:#000;font-size:13px">News Digest</b>
<span style="color:#000;font-size:11px;padding-left:8px">{TODAY}</span>
</td></tr>
<tr><td style="background:#f6f6ef;padding:8px 4px">
<table cellpadding="0" cellspacing="0" width="100%">
{body_html}
</table>
</td></tr>
</table>
</body>
</html>"""

payload = {
    "from": "${EMAIL_FROM}",
    "to": "${EMAIL_TO}",
    "subject": "News Digest - " + TODAY,
    "html": full_html
}

json_file = "/tmp/news-digest-email-payload.json"
with open(json_file, "w") as f:
    json.dump(payload, f)

result = subprocess.run([
    "curl", "-s", "-X", "POST", "https://api.resend.com/emails",
    "-H", "Authorization: Bearer ${RESEND_API_KEY}",
    "-H", "Content-Type: application/json",
    "-d", f"@{json_file}"
], capture_output=True, text=True)

import os
os.remove(json_file)

try:
    resp = json.loads(result.stdout)
    if "id" in resp:
        print(f"[email] Sent successfully. ID: {resp['id']}")
    else:
        print(f"[email] ERROR: {resp}")
        sys.exit(1)
except json.JSONDecodeError:
    print(f"[email] ERROR: Unexpected response: {result.stdout}")
    sys.exit(1)
PYEOF

echo "[email] Done."
