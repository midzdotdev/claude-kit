#!/usr/bin/env bash

# THRESHOLDS: token counts at which to warn, ascending. Each fires once per session.
THRESHOLDS=(300000 500000 700000)

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
jsonl=$(echo "$input" | jq -r '.transcript_path')

[ -z "$session_id" ] || [ "$session_id" = "null" ] && exit 0
[ -z "$jsonl" ] || [ "$jsonl" = "null" ] && exit 0
[ -f "$jsonl" ] || exit 0

flag="/tmp/claude-ctx-warned-$session_id"

tokens=$(python3 - "$jsonl" <<'PY'
import json, sys

path = sys.argv[1]
total = None
with open(path, encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue
        usage = obj.get("message", {}).get("usage")
        if not isinstance(usage, dict):
            continue
        total = (
            usage.get("input_tokens", 0)
            + usage.get("cache_read_input_tokens", 0)
            + usage.get("cache_creation_input_tokens", 0)
        )

print(total if total is not None else "")
PY
)

[ -z "$tokens" ] && exit 0

crossed=0
for t in "${THRESHOLDS[@]}"; do
  [ "$tokens" -ge "$t" ] && crossed="$t"
done
[ "$crossed" -eq 0 ] && exit 0

warned=0
[ -f "$flag" ] && warned=$(cat "$flag")
[ "$crossed" -le "$warned" ] && exit 0

ktokens=$(( tokens / 1000 ))

echo "$crossed" > "$flag"

jq -n --arg ctx "⚠️ Context is at ~${ktokens}k tokens. Ask the user if they'd like to /compact now to free up context." \
  '{hookSpecificOutput: {additionalContext: $ctx}}'

exit 0
