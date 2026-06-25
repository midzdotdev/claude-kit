#!/usr/bin/env bash
# claude-keepalive.sh — in-session auto-resume for the 5-hour usage limit (PoC).
#
# Arm this BEFORE you hit the limit, launched as a BACKGROUND task via Claude's
# Bash tool (run_in_background). It MUST be started by Claude itself: the harness
# only auto-re-invokes Claude when a task IT started finishes.
#
# It polls this session's transcript for the "session limit · resets <time>"
# error, then sleeps until that reset time (+buffer) and exits. The exit wakes
# Claude, which reads this output (the sentinel below) and continues.
#
# Fast smoke test (no real limit needed): KEEPALIVE_TEST_DELAY=20 wakes after 20s.

set -uo pipefail

POLL="${KEEPALIVE_POLL:-60}"
BUFFER="${KEEPALIVE_BUFFER:-90}"
SENTINEL="CLAUDE-KEEPALIVE-PROOF-7Q2K"

wake() {
  echo "$SENTINEL"
  echo "Usage-limit keepalive fired at $(date '+%Y-%m-%d %H:%M:%S %Z')."
  echo "The 5-hour session limit has reset. ACTION: confirm the in-session auto-resume worked (quote the token above), then continue the prior task."
  exit 0
}

if [ -n "${KEEPALIVE_TEST_DELAY:-}" ]; then
  echo "keepalive: TEST mode — waking in ${KEEPALIVE_TEST_DELAY}s"
  sleep "$KEEPALIVE_TEST_DELAY"
  wake
fi

session_id="${CLAUDE_CODE_SESSION_ID:-${1:-}}"
[ -z "$session_id" ] && { echo "keepalive: no CLAUDE_CODE_SESSION_ID"; exit 1; }

transcript="$(find "$HOME/.claude/projects" -name "$session_id.jsonl" 2>/dev/null | head -1)"
[ -z "$transcript" ] && { echo "keepalive: transcript not found for $session_id"; exit 1; }

echo "keepalive: armed for session $session_id"
echo "keepalive: watching $transcript (poll ${POLL}s, buffer ${BUFFER}s)"

while true; do
  reset_epoch="$(python3 - "$transcript" <<'PY'
import json, re, sys, datetime
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

path = sys.argv[1]
last_err = ""
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if o.get("type") != "assistant":
                continue
            if o.get("isApiErrorMessage") is True:
                c = o.get("message", {}).get("content")
                if isinstance(c, list):
                    last_err = " ".join(s.get("text", "") for s in c if isinstance(s, dict))
                elif isinstance(c, str):
                    last_err = c
                else:
                    last_err = ""
            else:
                last_err = ""  # a successful assistant turn supersedes a prior error
except FileNotFoundError:
    pass

m = re.search(r'session limit.*?resets\s+(\d{1,2})(?::(\d{2}))?\s*([ap]m)\s*\(([^)]+)\)', last_err, re.I)
if not m:
    sys.exit(0)
hh = int(m.group(1)) % 12 + (12 if m.group(3).lower() == "pm" else 0)
mm = int(m.group(2) or 0)
tz = None
if ZoneInfo is not None:
    try:
        tz = ZoneInfo(m.group(4))
    except Exception:
        tz = None
now = datetime.datetime.now(tz)
target = now.replace(hour=hh, minute=mm, second=0, microsecond=0)
if target <= now:
    target += datetime.timedelta(days=1)
print(int(target.timestamp()))
PY
)"
  if [ -n "$reset_epoch" ]; then
    now_epoch="$(date +%s)"
    wait_s=$(( reset_epoch + BUFFER - now_epoch ))
    [ "$wait_s" -lt 0 ] && wait_s=0
    echo "keepalive: limit detected — reset epoch $reset_epoch, sleeping ${wait_s}s"
    sleep "$wait_s"
    wake
  fi
  sleep "$POLL"
done
