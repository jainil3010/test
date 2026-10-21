---
name: claude-bridge
description: Send the user's message to the Claude Code session on machine B and return its reply.
---

# Claude bridge

When the user wants Claude Code on machine B to do something, run with the `exec` tool
(`host=node`, node `claude-b`, `timeoutSeconds` large enough for the task):

```bash
/home/USER/claude-bridge/claude-bridge.sh auto -- 'MESSAGE'
```

Rules:
- Put the user's text inside single quotes. Replace every `'` in it with `'\''`. Never use double quotes, backticks, `$(...)`, pipes or redirects (allowlist mode rejects them).
- Return the script's stdout to the user unchanged. If it starts with `bridge error:`, report that line and do not retry in a loop.
- If exec reports the command is still running, use `process poll`; do not start a second call for the same chat.
