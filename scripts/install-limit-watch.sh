#!/usr/bin/env bash
# install-limit-watch.sh — install the launchd LaunchAgent for claude-limit-watch.
# Idempotent: re-running reinstalls and reloads. Pass `uninstall` to remove.

set -euo pipefail

LABEL="dev.midz.claude-kit.limit-watch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCH="$SCRIPT_DIR/claude-limit-watch.sh"
STATE_DIR="$HOME/.claude/claude-kit"
CLAUDE_BIN="$(command -v claude || echo "$HOME/.local/bin/claude")"
INTERVAL="${LIMIT_WATCH_INTERVAL:-120}"
DOMAIN="gui/$(id -u)"

if [ "${1:-}" = "uninstall" ]; then
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  rm -f "$PLIST"
  echo "uninstalled $LABEL"
  exit 0
fi

[ -f "$WATCH" ] || { echo "watch script not found: $WATCH" >&2; exit 1; }
chmod +x "$WATCH"
mkdir -p "$STATE_DIR" "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>$WATCH</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_BIN</key>
    <string>$CLAUDE_BIN</string>
    <key>PATH</key>
    <string>$(dirname "$CLAUDE_BIN"):/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin</string>
  </dict>
  <key>StartInterval</key>
  <integer>$INTERVAL</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$STATE_DIR/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>$STATE_DIR/launchd.err.log</string>
</dict>
</plist>
EOF

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
launchctl bootstrap "$DOMAIN" "$PLIST"
launchctl enable "$DOMAIN/$LABEL"

echo "installed and loaded: $LABEL"
echo "  watch script : $WATCH"
echo "  claude bin   : $CLAUDE_BIN"
echo "  interval     : ${INTERVAL}s"
echo "  logs         : $STATE_DIR/limit-watch.log"
