#!/usr/bin/env bash
# claude-limit-watch.sh — external watcher for the 5-hour session limit.
#
# Run periodically by launchd (see install-limit-watch.sh). Each run scans
# recently-modified session transcripts; for any whose LAST assistant turn ended
# on "You've hit your session limit · resets <time>", it waits until that reset
# time has passed, then resumes the session headlessly:
#   claude -p --resume <session_id> "<resume prompt>"
#
# Because launchd owns this, it survives Claude session reloads, app restarts,
# and the limit interruption itself. Resume output goes to a per-session logfile.

set -uo pipefail

CLAUDE_BIN="${CLAUDE_BIN:-$HOME/.local/bin/claude}"
STATE_DIR="$HOME/.claude/claude-kit"
LOG="$STATE_DIR/limit-watch.log"
RESUME_PROMPT="${KEEPALIVE_RESUME_PROMPT:-The usage limit has reset. Continue the previous task where you left off.}"
BUFFER="${KEEPALIVE_BUFFER:-120}"
WINDOW_MIN="${KEEPALIVE_WINDOW_MIN:-360}"

mkdir -p "$STATE_DIR/handled"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') $*" >> "$LOG"; }

while IFS= read -r tp; do
  [ -f "$tp" ] || continue
  sid="$(basename "$tp" .jsonl)"

  parsed="$(python3 - "$tp" <<'PY'
import json, re, sys, datetime
try:
    from zoneinfo import ZoneInfo
except Exception:
    ZoneInfo = None

path = sys.argv[1]
last_err = ""
hit_ts = ""
cwd = ""
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
            if isinstance(o.get("cwd"), str) and o["cwd"]:
                cwd = o["cwd"]
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
                hit_ts = o.get("timestamp", "") or ""
            else:
                last_err = ""
                hit_ts = ""
except FileNotFoundError:
    sys.exit(0)

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

# Anchor the reset to the limit-hit timestamp (stable across runs), not to "now":
# the reset is the first occurrence of HH:MM at/after the moment the limit was hit.
try:
    hit = datetime.datetime.fromisoformat(hit_ts.replace("Z", "+00:00"))
    if tz is not None:
        hit = hit.astimezone(tz)
except Exception:
    hit = datetime.datetime.now(tz)
target = hit.replace(hour=hh, minute=mm, second=0, microsecond=0)
if target < hit:
    target += datetime.timedelta(days=1)
print(f"{int(target.timestamp())}\t{cwd}")
PY
)"
  [ -z "$parsed" ] && continue
  reset_epoch="${parsed%%	*}"
  cwd="${parsed#*	}"
  [ -z "$reset_epoch" ] && continue

  marker="$STATE_DIR/handled/${sid}-${reset_epoch}"
  [ -f "$marker" ] && continue

  now="$(date +%s)"
  if [ "$now" -ge "$(( reset_epoch + BUFFER ))" ]; then
    touch "$marker"
    log "resume: session $sid (reset $reset_epoch) in ${cwd:-$HOME}"
    ( cd "${cwd:-$HOME}" 2>/dev/null || cd "$HOME"
      "$CLAUDE_BIN" -p --resume "$sid" "$RESUME_PROMPT" >> "$STATE_DIR/resume-$sid.log" 2>&1 ) &
  else
    log "pending: session $sid limited; reset+buffer at $(( reset_epoch + BUFFER )) (now $now)"
  fi
done < <(find "$HOME/.claude/projects" -name '*.jsonl' -mmin "-$WINDOW_MIN" 2>/dev/null)
