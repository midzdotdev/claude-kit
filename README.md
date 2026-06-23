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

## Layout

```
.claude-plugin/
  plugin.json        # plugin manifest
  marketplace.json   # makes this repo self-installable
hooks/
  hooks.json         # Stop + PostCompact wiring
scripts/
  context-threshold-check.sh
  context-threshold-clear-flag.sh
```

## Requirements

`jq` and `python3` on `PATH` (both standard on macOS dev setups).
