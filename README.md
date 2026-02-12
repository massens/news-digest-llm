# News Digest LLM

An automated daily news digest system that aggregates content from multiple sources (Feedbin RSS, Hacker News, X/Twitter via RSSHub), generates an AI-powered summary using Claude, and delivers it to both Slack and email.

## Quick Start

```bash
# 1. Configure credentials
vim credentials.env  # Fill in all tokens and keys

# 2. Run the full pipeline
./scripts/run_all.sh

# 3. Or run individual scripts
./scripts/00_sync_x_following.sh
./scripts/01_fetch_feedbin.sh
./scripts/02_fetch_hn_best.sh
./scripts/03_refresh_x_feeds.sh
./scripts/04_summarize.sh
./scripts/05_post_slack.sh
./scripts/06_post_email.sh
```

## Setup

### Prerequisites
- macOS (uses `date -v` for date math)
- `curl`, `python3` installed
- Claude CLI (`claude`) installed and authenticated
- Slack workspace access
- Resend account (for email delivery)

### 1. Slack Bot Setup

1. Go to [api.slack.com/apps](https://api.slack.com/apps) and click **Create New App** > **From scratch**
2. Name it `News Digest Bot`, select your workspace
3. Go to **OAuth & Permissions** in the sidebar
4. Under **Bot Token Scopes**, add: `chat:write`
5. Click **Install to Workspace** at the top and authorize
6. Copy the **Bot User OAuth Token** (starts with `xoxb-`)
7. Paste it in `credentials.env` as `SLACK_BOT_TOKEN`
8. In Slack, create the `#news-digest` channel if it doesn't exist
9. In the channel, type `/invite @News Digest Bot` to add the bot

### 2. RSSHub on Railway

Your self-hosted RSSHub on Railway provides X/Twitter feeds.

1. Find your Railway app URL (e.g., `https://rsshub-production-xxxx.up.railway.app`)
2. Make sure `TWITTER_AUTH_TOKEN` is set as an environment variable in Railway
3. Update `RSSHUB_BASE_URL` in `credentials.env`
4. Test: `curl https://YOUR-RSSHUB.up.railway.app/twitter/user/simonw`

### 3. Resend (Email Delivery)

1. Sign up at [resend.com](https://resend.com)
2. Create an API key (sending-only is fine)
3. Add it to `credentials.env` as `RESEND_API_KEY`
4. Optionally verify your domain at resend.com/domains to send from a custom address (defaults to `onboarding@resend.dev`)

### 4. Credentials

Edit `credentials.env` with your actual values:
- `FEEDBIN_EMAIL` / `FEEDBIN_PASSWORD` - Feedbin account
- `X_AUTH_TOKEN` - X.com cookie auth token
- `RSSHUB_BASE_URL` - your Railway RSSHub URL
- `SLACK_BOT_TOKEN` - from step 1 above
- `SLACK_CHANNEL` - channel ID (e.g., `C0XXXXXXXXX`)
- `RESEND_API_KEY` - from step 3 above
- `EMAIL_TO` - recipient email address
- `EMAIL_FROM` - sender address (must be verified domain or `onboarding@resend.dev`)

## Cron Job

### Enable (runs daily at 8:00 AM)

```bash
(crontab -l 2>/dev/null; echo "0 8 * * * PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$HOME/.local/bin $HOME/code/news-digest-llm/scripts/run_all.sh >> $HOME/code/news-digest-llm/outputs/cron.log 2>&1") | crontab -
```

### Disable

```bash
crontab -l | grep -v "news-digest-llm" | crontab -
```

### Check status

```bash
crontab -l
tail -50 ~/code/news-digest-llm/outputs/cron.log
```

**Note:** Your Mac must be awake at 8 AM for cron to fire. If asleep, macOS will run it when the machine next wakes.

## Project Structure

```
news-digest-llm/
├── PRD.md                          # Product requirements
├── README.md                       # This file
├── credentials.env                 # API keys and tokens (gitignored)
├── .gitignore
├── prompts/
│   └── summarize.md                # Claude prompt template
├── scripts/
│   ├── 00_sync_x_following.sh      # Sync X following list → Feedbin
│   ├── 01_fetch_feedbin.sh         # Fetch unread RSS entries
│   ├── 02_fetch_hn_best.sh         # Fetch HN best stories
│   ├── 03_refresh_x_feeds.sh       # Fetch X home timeline via RSSHub
│   ├── 04_summarize.sh             # Generate summary with Claude
│   ├── 05_post_slack.sh            # Post to Slack
│   ├── 06_post_email.sh            # Send HTML email via Resend
│   └── run_all.sh                  # Master orchestrator
└── outputs/
    ├── raw/
    │   └── YYYY-MM-DD/
    │       ├── feedbin.txt          # Raw Feedbin entries
    │       ├── hn_best.txt          # Raw HN stories
    │       ├── x_feeds.txt          # Raw X/Twitter feeds
    │       └── status.json          # Pipeline step statuses
    ├── summaries/
    │   └── YYYY-MM-DD.md            # Generated summary
    └── run_YYYY-MM-DD.log           # Execution log
```

## Scripts

| Script | Purpose | Dependencies |
|--------|---------|-------------|
| `00_sync_x_following.sh` | Fetches your X following list via GraphQL, creates Feedbin subscriptions for new follows via RSSHub | X auth token, Feedbin creds |
| `01_fetch_feedbin.sh` | Fetches all unread Feedbin entries from last 24h | Feedbin credentials |
| `02_fetch_hn_best.sh` | Fetches top 30 stories from HN /best | None (public API) |
| `03_refresh_x_feeds.sh` | Fetches full X home timeline via RSSHub `/twitter/home_latest` | RSSHub URL, X auth token |
| `04_summarize.sh` | Pipes all raw data to Claude CLI for AI summary | Claude CLI |
| `05_post_slack.sh` | Posts the summary to Slack #news-digest | Slack bot token |
| `06_post_email.sh` | Converts Slack mrkdwn to HN-style HTML and sends via Resend | Resend API key |
| `run_all.sh` | Runs all scripts in sequence with error handling and alert injection | All above |

## Pipeline Flow

```
00 Sync X following → Feedbin subscriptions
01 Fetch Feedbin    ─┐
02 Fetch HN Best    ─┤ raw data
03 Fetch X timeline ─┘
04 Summarize with Claude
   ↓
   Inject alerts (if any step failed)
   ↓
05 Post to Slack ─────── #news-digest
06 Send HTML email ───── inbox
```

## Alert System

When any pipeline step fails, an alert block is automatically prepended to the digest (both Slack and email). Alerts include actionable instructions for fixing the issue:

- **X auth token expired** → instructions to refresh the cookie and update Railway
- **Feedbin fetch failed** → check credentials
- **X following sync failed** → new follows won't appear
- **HN fetch failed** → HN section missing

## Customization

### Change the summary style
Edit `prompts/summarize.md` to adjust what Claude focuses on, the output format, or priority order.

### Change delivery time
Update the cron schedule (first two numbers = minute hour):
- `0 7 * * *` = 7:00 AM
- `0 8 * * *` = 8:00 AM (default)
- `30 8 * * *` = 8:30 AM

### Change Slack channel
Update `SLACK_CHANNEL` in `credentials.env`.

### Change email recipient
Update `EMAIL_TO` in `credentials.env`.

## Troubleshooting

- **X auth token expired**: Get a fresh token from browser → x.com → DevTools → Application → Cookies → `auth_token`. Update in `credentials.env` and on Railway: `railway variables set TWITTER_AUTH_TOKEN="<new_token>" && railway redeploy --yes`
- **Feedbin auth fails**: Check credentials in `credentials.env`
- **Claude returns empty**: Make sure `claude` CLI is authenticated (`claude --version`)
- **Slack post fails**: Ensure bot is invited to the channel and token has `chat:write` scope
- **Email fails with 403**: Verify your sending domain at resend.com/domains, or use `onboarding@resend.dev`
- **RSSHub timeout**: Check Railway deployment status (`railway status`)
- **Cron not running**: Check `crontab -l`, ensure Mac was awake at scheduled time, check `outputs/cron.log`
- **X sync finds 0 accounts**: X GraphQL query IDs may have rotated — the script auto-discovers them from main.js, but X may have changed the bundle structure
