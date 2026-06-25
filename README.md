# claude-kit

A self-hosted [Claude Code](https://claude.com/claude-code) plugin bundling James's
reusable primitives — currently hooks, with room to grow (commands, agents, settings).

## Install

```bash
/plugin marketplace add midzdotdev/claude-kit
/plugin install claude-kit@claude-kit
```

`/plugin marketplace add` also accepts the full repo URL. Once installed, the hooks
wire themselves up automatically — no manual `settings.json` editing.

## What's inside

### Context-threshold warnings (hooks)

After every response, a `Stop` hook checks how full the context window is for the
current session and, once input tokens cross a configured tier, injects a message
prompting Claude to ask whether you'd like to `/compact`.

- **Tiers** live in `THRESHOLDS` at the top of
  [`scripts/context-threshold-check.sh`](scripts/context-threshold-check.sh)
  (default `300000 500000 700000`). Each tier fires at most once per session.
- A `PostCompact` hook clears the per-session flag, so warnings resume after a
  compaction.
- Current context size is read from the session's JSONL transcript
  (`input_tokens + cache_read_input_tokens + cache_creation_input_tokens` of the
  last assistant turn).

State is a single flag file at `/tmp/claude-ctx-warned-<session_id>` recording the
highest tier already warned.

### 5-hour-limit keepalive (PoC) — `/keepalive`

In-session auto-resume after the 5-hour usage limit. You arm it (via `/keepalive`,
which has Claude launch `scripts/claude-keepalive.sh` as a background task). The
watcher polls this session's transcript; when the
`You've hit your session limit · resets <time>` error appears, it waits until the
stated reset time (+buffer) and exits. Because the harness re-invokes Claude when a
Claude-started background task finishes, that exit **wakes the same session** to
continue — no headless run, no launchd.

Constraints (PoC): arm it *before* hitting the limit (a limited session can't start
anything); the terminal must stay open; and re-invocation after a limit-terminated
turn is the behaviour we're validating. On wake it emits the sentinel
`CLAUDE-KEEPALIVE-PROOF-7Q2K`. Smoke-test the wake path without a real limit via
`KEEPALIVE_TEST_DELAY=20`.

**Known limitation:** a Claude-started background task does **not** survive a session
reload/continuation (context summarization, app restart) — which a long session hits
before the 5-hour limit. So the in-session keepalive is unreliable for the real case;
prefer the launchd watcher below.

### 5-hour-limit watcher (launchd) — `/limit-watch`

External LaunchAgent that survives session reloads, app restarts, and the limit
interruption (launchd owns it, not the Claude process). It runs every ~2 min,
scans recently-modified transcripts for any whose latest turn ended on
`You've hit your session limit · resets <time>`, and once that reset has passed
resumes the session **headlessly**:

```
claude -p --resume <session_id> "The usage limit has reset. Continue…"
```

Install: `/limit-watch` (runs `scripts/install-limit-watch.sh`; `uninstall` to remove).
The reset moment is anchored to the limit-hit timestamp in the transcript, so it's
stable across the periodic re-scans. Fires are idempotent (a `handled/<sid>-<reset>`
marker). Resume output lands in `~/.claude/claude-kit/resume-<session_id>.log`, **not**
your live session — this trades same-session continuation for reliability.

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest
  marketplace.json   # makes this repo self-installable
hooks/
  hooks.json         # Stop + PostCompact wiring
commands/
  keepalive.md       # /keepalive — arm the 5h-limit watcher
scripts/
  context-threshold-check.sh
  context-threshold-clear-flag.sh
  claude-keepalive.sh        # in-session keepalive (fragile; see note)
  claude-limit-watch.sh      # external launchd watcher (robust)
  install-limit-watch.sh     # installs the LaunchAgent
```

## Requirements

`jq` and `python3` on `PATH` (both standard on macOS dev setups).
