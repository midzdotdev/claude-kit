---
description: Arm in-session auto-resume for the 5-hour usage limit (keepalive watcher).
---

Arm the in-session keepalive so this session auto-continues after the 5-hour usage limit resets.

Launch the watcher as a BACKGROUND task using the Bash tool with `run_in_background: true` — it must be started by you (the harness only re-invokes you when a task *you* started exits):

```
"${CLAUDE_PLUGIN_ROOT}/scripts/claude-keepalive.sh"
```

If `${CLAUDE_PLUGIN_ROOT}` is not set in the shell, resolve the script under the installed plugin path (`~/.claude/plugins/cache/claude-kit/claude-kit/<version>/scripts/claude-keepalive.sh`) or the working copy at `~/code/claude-kit/scripts/claude-keepalive.sh`.

The watcher polls this session's transcript; when the `session limit · resets <time>` error appears it sleeps until reset (+buffer) then exits, which wakes you to continue.

After arming, tell the user the keepalive is running and that they must keep this session/terminal open for it to fire.
