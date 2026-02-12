#!/usr/bin/env bash
# 00_sync_x_following.sh - Sync X following list → Feedbin subscriptions via RSSHub
# Creates Feedbin RSS subscriptions for each account @massens follows on X.
# Runs before the fetch scripts so new follows are picked up immediately.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
source "$PROJECT_DIR/credentials.env"
export X_AUTH_TOKEN X_USERNAME X_BEARER_TOKEN RSSHUB_BASE_URL FEEDBIN_EMAIL FEEDBIN_PASSWORD

STATUS_FILE="${STATUS_FILE:-$PROJECT_DIR/outputs/raw/$(date +%Y-%m-%d)/status.json}"
export STATUS_FILE
mkdir -p "$(dirname "$STATUS_FILE")"

echo "[sync_x] Syncing X following list to Feedbin..."

python3 << 'PYEOF'
import json, subprocess, sys, urllib.parse, os, time

AUTH_TOKEN = os.environ.get("X_AUTH_TOKEN", "") or "PLACEHOLDER"
RSSHUB_BASE = os.environ.get("RSSHUB_BASE_URL", "") or "PLACEHOLDER"
FEEDBIN_EMAIL = os.environ.get("FEEDBIN_EMAIL", "") or "PLACEHOLDER"
FEEDBIN_PASS = os.environ.get("FEEDBIN_PASSWORD", "") or "PLACEHOLDER"

X_USERNAME = os.environ.get("X_USERNAME", "") or "massens"
BEARER = os.environ.get("X_BEARER_TOKEN", "") or "AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"

def write_status(key, status, msg=""):
    """Append status to the daily status file."""
    sf = os.environ.get("STATUS_FILE", "/tmp/news-digest-status.json")
    try:
        with open(sf) as f:
            data = json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        data = {}
    data[key] = {"status": status, "message": msg}
    with open(sf, "w") as f:
        json.dump(data, f, indent=2)

def curl_json(args):
    r = subprocess.run(["curl", "-s", "--max-time", "15"] + args, capture_output=True, text=True)
    if not r.stdout.strip():
        return None
    try:
        return json.loads(r.stdout)
    except json.JSONDecodeError:
        return None

# --- Step 1: Get CSRF token ---
print("[sync_x] Getting CSRF token...")
cookie_jar = "/tmp/x_cookies_sync.txt"
subprocess.run(["curl", "-s", "-c", cookie_jar, "-b", f"auth_token={AUTH_TOKEN}", "https://x.com", "-o", "/dev/null"], capture_output=True)

ct0 = ""
try:
    for line in open(cookie_jar):
        if "ct0" in line:
            ct0 = line.strip().split()[-1]
            break
except FileNotFoundError:
    pass

if not ct0:
    print("[sync_x] ERROR: Could not get CSRF token. Auth token may be expired.")
    write_status("x_auth", "error", "X auth token expired - could not get CSRF token. Refresh at: browser → x.com → DevTools → Application → Cookies → auth_token")
    sys.exit(1)

# --- Step 2: Get current GraphQL query IDs from main.js ---
print("[sync_x] Fetching current GraphQL query IDs...")
page_r = subprocess.run(["curl", "-s", "--max-time", "15", "-b", f"auth_token={AUTH_TOKEN}", "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36", "https://x.com"], capture_output=True, text=True)

import re
js_urls = re.findall(r'https://abs\.twimg\.com/responsive-web/client-web/main\.[^"]+\.js', page_r.stdout)
if not js_urls:
    print("[sync_x] ERROR: Could not find X main.js bundle")
    write_status("x_auth", "error", "Could not load X.com - auth token may be expired")
    sys.exit(1)

js_r = subprocess.run(["curl", "-s", "--max-time", "30", js_urls[0]], capture_output=True, text=True)
query_ids = {}
for m in re.finditer(r'queryId:"([^"]+)",operationName:"(Following|UserByScreenName)"', js_r.stdout):
    query_ids[m.group(2)] = m.group(1)

if "Following" not in query_ids:
    print("[sync_x] ERROR: Could not find Following query ID")
    write_status("x_sync", "error", "X GraphQL query IDs changed - sync script needs update")
    sys.exit(1)

print(f"[sync_x] Query IDs: {query_ids}")

# --- Step 3: Build features dict ---
features = {"responsive_web_graphql_exclude_directive_enabled":True,"verified_phone_label_enabled":False,"responsive_web_graphql_skip_user_profile_image_extensions_enabled":False,"responsive_web_graphql_timeline_navigation_enabled":True,"responsive_web_enhance_cards_enabled":False,"view_counts_everywhere_api_enabled":True,"creator_subscriptions_tweet_preview_api_enabled":True,"longform_notetweets_rich_text_read_enabled":True,"responsive_web_edit_tweet_api_enabled":True,"tweetypie_unmention_optimization_enabled":True,"longform_notetweets_inline_media_enabled":True,"standardized_nudges_misinfo":True,"tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled":True,"longform_notetweets_consumption_enabled":True,"responsive_web_media_download_video_enabled":False,"rweb_video_timestamps_enabled":True,"freedom_of_speech_not_reach_fetch_enabled":True,"rweb_tipjar_consumption_enabled":True,"hidden_profile_subscriptions_enabled":True,"subscriptions_verification_info_is_identity_verified_enabled":True,"subscriptions_verification_info_verified_since_enabled":True,"highlights_tweets_tab_ui_enabled":True,"subscriptions_feature_can_gift_premium":True,"responsive_web_grok_share_attachment_enabled":True,"responsive_web_grok_imagine_annotation_enabled":True,"responsive_web_twitter_article_tweet_consumption_enabled":True,"tweet_awards_web_tipping_enabled":True,"rweb_video_screen_enabled":True,"responsive_web_grok_analyze_button_fetch_trends_enabled":True,"post_ctas_fetch_enabled":True,"premium_content_api_read_enabled":True,"responsive_web_grok_analysis_button_from_backend":True,"responsive_web_grok_image_annotation_enabled":True,"graphql_is_translatable_rweb_tweet_is_translatable_enabled":True,"responsive_web_grok_annotations_enabled":True,"communities_web_enable_tweet_community_results_fetch":True,"responsive_web_profile_redirect_enabled":True,"responsive_web_grok_community_note_auto_translation_is_enabled":True,"responsive_web_grok_show_grok_translated_post":True,"articles_preview_enabled":True,"responsive_web_grok_analyze_post_followups_enabled":True,"c9s_tweet_anatomy_moderator_badge_enabled":True,"responsive_web_jetfuel_frame":True,"profile_label_improvements_pcf_label_in_post_enabled":True}

headers = [
    "-b", f"auth_token={AUTH_TOKEN}; ct0={ct0}",
    "-H", f"Authorization: Bearer {BEARER}",
    "-H", f"X-Csrf-Token: {ct0}",
    "-H", "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
]

# --- Step 4: Get user ID ---
print(f"[sync_x] Getting user ID for @{X_USERNAME}...")
user_vars = urllib.parse.quote(json.dumps({"screen_name": X_USERNAME, "withSafetyModeUserFields": True}))
feat_str = urllib.parse.quote(json.dumps(features))
user_data = curl_json(headers + [f"https://x.com/i/api/graphql/{query_ids.get('UserByScreenName','')}/UserByScreenName?variables={user_vars}&features={feat_str}"])

if not user_data or "data" not in user_data:
    print(f"[sync_x] ERROR: Could not get user ID. Response: {str(user_data)[:200]}")
    write_status("x_auth", "error", "X auth token expired or invalid")
    sys.exit(1)

user_id = user_data["data"]["user"]["result"]["rest_id"]
friends_count = user_data["data"]["user"]["result"].get("legacy",{}).get("friends_count", 0)
print(f"[sync_x] User ID: {user_id}, Following: {friends_count}")

# --- Step 5: Fetch all followed accounts (paginated) ---
print("[sync_x] Fetching following list...")
all_following = []
cursor = None

for page in range(10):  # max 10 pages = 2000 accounts
    variables = {"userId": user_id, "count": 200, "includePromotedContent": False}
    if cursor:
        variables["cursor"] = cursor

    vars_str = urllib.parse.quote(json.dumps(variables))
    url = f"https://x.com/i/api/graphql/{query_ids['Following']}/Following?variables={vars_str}&features={feat_str}"
    data = curl_json(headers + [url])

    if not data or "data" not in data:
        print(f"[sync_x] WARNING: Page {page+1} failed")
        break

    instructions = data["data"]["user"]["result"]["timeline"]["timeline"]["instructions"]
    page_users = []
    next_cursor = None

    for inst in instructions:
        for entry in inst.get("entries", []):
            content = entry.get("content", {})
            # User entries
            item = content.get("itemContent", {})
            result = item.get("user_results", {}).get("result", {})
            sn = result.get("core", {}).get("screen_name", "")
            if sn:
                page_users.append(sn)
            # Cursor entries
            if content.get("cursorType") == "Bottom":
                next_cursor = content.get("value")

    all_following.extend(page_users)
    print(f"[sync_x] Page {page+1}: {len(page_users)} accounts (total: {len(all_following)})")

    if not next_cursor or not page_users:
        break
    cursor = next_cursor
    time.sleep(1)

print(f"[sync_x] Total following: {len(all_following)}")

if not all_following:
    write_status("x_sync", "error", "Could not fetch X following list - got 0 accounts")
    sys.exit(1)

# --- Step 6: Get current Feedbin subscriptions ---
print("[sync_x] Fetching current Feedbin subscriptions...")
subs_data = curl_json(["-u", f"{FEEDBIN_EMAIL}:{FEEDBIN_PASS}", "https://api.feedbin.com/v2/subscriptions.json"])

if subs_data is None:
    print("[sync_x] ERROR: Could not fetch Feedbin subscriptions")
    write_status("feedbin", "error", "Feedbin API unreachable")
    sys.exit(1)

# Find existing Twitter/RSSHub subscriptions
existing_twitter = {}  # screen_name_lower -> subscription
for sub in subs_data:
    feed_url = sub.get("feed_url", "")
    title = sub.get("title", "")
    # Match RSSHub twitter feeds
    m = re.search(r'/twitter/user/(\w+)', feed_url)
    if m:
        existing_twitter[m.group(1).lower()] = sub
    # Also match by title "Twitter @username"
    m2 = re.match(r'Twitter @(.+)', title)
    if m2:
        existing_twitter[m2.group(1).lower()] = sub

print(f"[sync_x] Existing Twitter subscriptions in Feedbin: {len(existing_twitter)}")

# --- Step 7: Create missing subscriptions ---
new_count = 0
errors = 0
for username in all_following:
    if username.lower() in existing_twitter:
        continue

    feed_url = f"{RSSHUB_BASE}/twitter/user/{username}"
    print(f"[sync_x] Adding @{username} -> {feed_url}")

    result = subprocess.run([
        "curl", "-s", "--max-time", "10",
        "-X", "POST",
        "-u", f"{FEEDBIN_EMAIL}:{FEEDBIN_PASS}",
        "-H", "Content-Type: application/json",
        "-d", json.dumps({"feed_url": feed_url}),
        "https://api.feedbin.com/v2/subscriptions.json"
    ], capture_output=True, text=True)

    try:
        resp = json.loads(result.stdout)
        if "id" in resp:
            new_count += 1
        elif "status" in resp and resp["status"] == 404:
            print(f"[sync_x]   Feed not found for @{username}")
            errors += 1
        else:
            print(f"[sync_x]   Response: {result.stdout[:100]}")
    except json.JSONDecodeError:
        print(f"[sync_x]   Bad response for @{username}")
        errors += 1

    time.sleep(0.5)  # rate limit

print(f"[sync_x] Done. Added {new_count} new subscriptions, {errors} errors")
write_status("x_sync", "ok", f"Synced {len(all_following)} accounts, {new_count} new, {errors} errors")
PYEOF

echo "[sync_x] Done."
