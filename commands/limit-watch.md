---
description: Install/manage the external launchd watcher that auto-resumes sessions after the 5-hour limit resets.
---

Install the launchd LaunchAgent that watches for the 5-hour session limit and resumes sessions headlessly once it resets. Unlike the in-session `/keepalive`, this survives session reloads, app restarts, and the limit itself, because launchd owns it.

Run the installer (Bash tool):

```
"${CLAUDE_PLUGIN_ROOT}/scripts/install-limit-watch.sh"
```

To remove it: run the same script with the `uninstall` argument.

If `${CLAUDE_PLUGIN_ROOT}` is unset, use the installed plugin path or the working copy at `~/code/claude-kit/scripts/install-limit-watch.sh`.

After installing, tell the user it's loaded, where the logs are (`~/.claude/claude-kit/limit-watch.log`), and that resumed turns run headlessly into `~/.claude/claude-kit/resume-<session_id>.log` (not the live TUI).
