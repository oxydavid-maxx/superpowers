#!/usr/bin/env bash
# serve-tunnel.sh — Serve a local folder to the user as a throwaway public URL.
#
# WHY: When the user runs Claude on the always-on workstation but views from
# claude web / phone, they cannot see local files. This serves a folder from
# THIS machine (localhost) and exposes it via a cloudflared quick tunnel
# (random *.trycloudflare.com). Content never leaves the machine except as
# proxied HTTP; no third-party upload, no account, no API key.
#
# USAGE:  bash ~/.claude/lib/serve-tunnel.sh <dir> [port]
# OUTPUT: prints PUBLIC_URL (and keeps server+tunnel running in bg).
# STOP:   kill the printed PIDs.
#
# ROBUSTNESS (fix 2026-06-24, recurring "served the WRONG app" bug):
#   The old version did `curl localhost:PORT && skip starting our server`, which
#   treated ANY app responding on PORT as "ours" — so when PORT was occupied by a
#   different service (e.g. the calorie app / a watchdog port) it tunneled to that
#   foreign app. Now we write a unique TOKEN into <dir>, only reuse a port that
#   serves OUR token, scan for a free port otherwise, and VERIFY our content is
#   served before tunneling — failing loudly instead of ever serving the wrong app.
#
# NOTE: requires real network egress (cloudflared). The URL is EPHEMERAL.

set -u
DIR="${1:?usage: serve-tunnel.sh <dir> [port]}"
REQ_PORT="${2:-8899}"
[ -d "$DIR" ] || { echo "ERROR: dir not found: $DIR" >&2; exit 1; }
command -v cloudflared >/dev/null 2>&1 || { echo "ERROR: cloudflared not installed" >&2; exit 1; }
DIR="${DIR%/}"
LOG="$DIR/_tunnel.log"

# Unique token proving a port serves OUR content (not a foreign app on that port).
TOKEN="serve-$$-${RANDOM}${RANDOM}"
printf '%s' "$TOKEN" > "$DIR/_serve_token.txt"

_serves_our_token() {  # $1=port -> 0 iff that port returns OUR token
  [ "$(curl -s --max-time 2 "http://127.0.0.1:$1/_serve_token.txt" 2>/dev/null)" = "$TOKEN" ]
}
_port_responds() {     # $1=port -> 0 iff anything answers HTTP there
  curl -s -o /dev/null --max-time 2 "http://127.0.0.1:$1/" 2>/dev/null
}

# 1) Choose a port: reuse one already serving OUR token, else the first FREE port.
#    Never reuse a port held by a foreign app (that was the bug).
PORT=""; REUSE=0
for cand in $(seq "$REQ_PORT" $((REQ_PORT + 40))); do
  if _serves_our_token "$cand"; then PORT="$cand"; REUSE=1; break; fi
  if ! _port_responds "$cand"; then PORT="$cand"; REUSE=0; break; fi
  echo "port $cand is busy with a FOREIGN app -> trying next" >&2
done
[ -n "$PORT" ] || { echo "ERROR: no free port in ${REQ_PORT}..$((REQ_PORT + 40))" >&2; exit 1; }

# 2) Start our static server (unless a prior run of ours already owns the port).
if [ "$REUSE" != "1" ]; then
  nohup python -m http.server "$PORT" --bind 127.0.0.1 --directory "$DIR" >"$DIR/_http.log" 2>&1 &
  echo "http.server pid=$! on 127.0.0.1:$PORT (dir=$DIR)"
fi

# 3) VERIFY our content is actually served before tunneling. Fail loudly — never
#    silently tunnel to whatever happens to be on the port.
ok=0
for _ in $(seq 1 12); do _serves_our_token "$PORT" && { ok=1; break; }; sleep 1; done
[ "$ok" = "1" ] || { echo "ERROR: 127.0.0.1:$PORT is NOT serving our content; refusing to tunnel" >&2; tail -8 "$DIR/_http.log" >&2; exit 1; }
echo "verified: 127.0.0.1:$PORT serves OUR content (token ok, dir=$DIR)"

# 4) Quick tunnel to the VERIFIED port.
nohup cloudflared tunnel --url "http://127.0.0.1:$PORT" --no-autoupdate >"$LOG" 2>&1 &
echo "cloudflared pid=$!"

# 5) Wait for the public URL.
URL=""
for _ in $(seq 1 20); do
  URL=$(grep -oE "https://[a-z0-9-]+\.trycloudflare\.com" "$LOG" | head -1)
  [ -n "$URL" ] && break
  sleep 1
done
[ -n "$URL" ] || { echo "ERROR: no URL yet; tail $LOG" >&2; tail -8 "$LOG" >&2; exit 1; }
echo "PUBLIC_URL: $URL"
