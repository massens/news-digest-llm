# News Digest LLM - Product Requirements Document

## Overview
An automated daily news digest system that aggregates content from multiple sources, generates an AI-powered summary tailored to Marc Assens (CEO/CTO of Happy Scribe), and delivers it to Slack and email every morning.

## Goal
Make Marc the most informed and up-to-date CEO possible by delivering a curated, intelligent summary of all relevant news every day.

## User Profile
- **Name**: Marc Assens
- **Role**: CEO/CTO of Happy Scribe
- **Company**: Happy Scribe (transcription, subtitles, translation SaaS)
- **Interests**:
  - Anything that could affect Happy Scribe (speech-to-text, AI transcription, subtitles, video AI, competitor moves, SaaS market shifts)
  - AI-native engineering practices (how the best engineers build with AI)
  - Major AI industry news (model releases, funding rounds, infrastructure, open source)
  - Startup/tech ecosystem trends

## Data Sources

### 1. Feedbin RSS
- Marc's Feedbin account aggregates 130+ feeds including:
  - Simon Willison's blog and newsletter
  - The Pragmatic Engineer
  - Anthropic Engineering Blog
  - r/ClaudeAI subreddit
  - 120+ X/Twitter accounts via RSSHub (auto-synced from X following list)
  - Various tech blogs and newsletters
- **API**: REST API with basic auth at `api.feedbin.com/v2/`
- **Scope**: All unread entries from the last 24 hours

### 2. X/Twitter via RSSHub
- Self-hosted RSSHub on Railway provides X/Twitter feeds
- Primary method: `/twitter/home_latest` fetches the full chronological home timeline in a single request
- Fallback: fetches individual key accounts if `home_latest` fails
- Auth token provides access to tweets from followed accounts

### 3. X Following Sync
- Daily sync of @massens's X following list to Feedbin
- Uses X's GraphQL API to fetch the full following list (paginated)
- Auto-discovers current GraphQL query IDs from X's main.js bundle (survives X deploys)
- Creates Feedbin RSS subscriptions via RSSHub for any new follows
- New follows on X automatically appear in the next day's digest

### 4. Hacker News Best
- Top stories from `https://news.ycombinator.com/best` via Firebase API
- Fetches top 30 stories with titles, URLs, points, and comment counts

## Output

### Slack Message (#news-digest)
- Posted daily at 8:00 AM CET
- Rich Slack mrkdwn formatting with sections, bold, links
- Organized by relevance categories:
  1. **Directly Relevant to Happy Scribe** - speech/transcription/AI competitors
  2. **AI-Native Engineering** - how to build better with AI
  3. **Major AI Industry News** - model releases, funding, infrastructure
  4. **Hacker News Highlights** - top stories from HN
- Every item's title is a clickable hyperlink to the source
- Summary is concise but comprehensive (aim for 3-5 min read)

### HTML Email
- Sent daily via Resend API as a parallel delivery mechanism
- HN-style minimal design: Verdana font, cream background, orange header bar, dense text layout
- Full width, numbered items, black underlined title links, gray descriptions
- Converts Slack mrkdwn format to HTML automatically

### Alert System
- Each pipeline step writes its status to `outputs/raw/YYYY-MM-DD/status.json`
- If any step fails, an alert block is prepended to the digest before delivery
- Alerts include actionable fix instructions (e.g., how to refresh expired auth tokens)
- Alerts appear in both Slack and email deliveries

### Persisted Files
- **Raw data**: `outputs/raw/YYYY-MM-DD/{feedbin,hn_best,x_feeds}.txt`
- **Status**: `outputs/raw/YYYY-MM-DD/status.json`
- **Summary**: `outputs/summaries/YYYY-MM-DD.md`
- **Logs**: `outputs/run_YYYY-MM-DD.log`

## Architecture

### Pipeline (executed sequentially by `run_all.sh`)
0. `00_sync_x_following.sh` - Sync X following list → Feedbin subscriptions
1. `01_fetch_feedbin.sh` - Fetch unread Feedbin entries from last 24h
2. `02_fetch_hn_best.sh` - Fetch HN best stories
3. `03_refresh_x_feeds.sh` - Fetch X home timeline via RSSHub
4. `04_summarize.sh` - Run Claude CLI to generate summary from all raw data
5. Inject alerts into summary if any prior step failed
6. `05_post_slack.sh` - Post summary to Slack #news-digest
7. `06_post_email.sh` - Send HN-style HTML email via Resend

### Scheduling
- macOS cron job runs `run_all.sh` at 8:00 AM CET daily
- Explicit PATH set in crontab for `claude`, `python3`, `curl` availability
- Can be manually triggered anytime via `./scripts/run_all.sh`

## Requirements

### Functional
- FR1: System fetches all unread Feedbin entries from the last 24 hours
- FR2: System fetches top stories from Hacker News /best via Firebase API
- FR3: System fetches X home timeline via RSSHub `/twitter/home_latest`
- FR4: System syncs X following list to Feedbin subscriptions daily
- FR5: System generates an AI summary using Claude CLI, tailored to Marc's interests
- FR6: System posts formatted summary to Slack #news-digest with hyperlinked titles
- FR7: System sends formatted HTML email via Resend with HN-style minimal design
- FR8: System persists raw data, status, and summaries to disk with date-based directory structure
- FR9: System runs automatically every morning via cron
- FR10: Each script can be run independently for testing
- FR11: System alerts Marc when any pipeline step fails, with actionable fix instructions

### Non-Functional
- NFR1: Total execution time < 5 minutes
- NFR2: Graceful failure handling (one source failing doesn't block others)
- NFR3: No sensitive credentials in git
- NFR4: Idempotent - running twice on the same day overwrites, doesn't duplicate
- NFR5: Summary includes hyperlinked titles for every referenced item
- NFR6: X GraphQL query IDs auto-discovered from main.js (survives X deploys)

## Success Criteria
1. Each sub-script runs independently and produces correct output
2. End-to-end run produces a summary in both Slack and email with all sources represented
3. Raw data files and status are persisted correctly
4. Cron job fires reliably every morning
5. New X follows automatically appear in the next day's digest
6. Pipeline failures produce visible alerts in the digest with fix instructions
7. Marc reads the digest and finds it genuinely useful for his day
