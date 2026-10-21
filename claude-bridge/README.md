# Phone (C) → OpenClaw (A) → Claude Code (B)

WhatsApp/Discord → OpenClaw gateway on A → `exec host=node` → `claude-bridge.sh` on B → `claude -p --resume`.

Files: `claude-bridge.sh` (runs on B), `skill/claude-bridge/SKILL.md` (tells the OpenClaw agent how to call it).

## Verified from OpenClaw docs (npm `openclaw@2026.10.5`, `docs/`)
- Node host on B runs commands for the gateway on A: `openclaw node run --host <A> --port 18789` (nodes/node-host.md).
- Route exec to B: `openclaw config set tools.exec.host node`, `tools.exec.node "<name>"`, `tools.exec.mode allowlist`; allowlist the script: `openclaw approvals allowlist add --node <name> "/abs/path/claude-bridge.sh"` (nodes/node-exec.md).
- ACPX routes cannot dispatch to a paired device (nodes/node-host.md), so ACP alone runs Claude on A.
- Allowlist mode rejects `$()`/backticks (even in double quotes) and redirections; single quotes keep `$()` literal (tools/exec-approvals-advanced.md).
- The `exec` tool has no stdin parameter (tools/exec.md), so the skill passes the message as a single-quoted argument. This is the residual risk: the model must quote correctly. Keep `BRIDGE_ALLOWED_TOOLS` narrow so a bad message can do little on B.
- Node-hosted skills: a skill dir under `~/.openclaw/skills/<name>/` on B is published to the gateway; dir name must equal `name` (nodes/mcp-and-skills.md). Install `skill/claude-bridge` there and restart the node host.
- `OPENCLAW_CHANNEL_CONTEXT` (JSON with `senderId`, `chatId`) is injected by nodes advertising `system.run.execution-context.v1` (nodes/node-exec.md). `auto` depends on it; untested here. Otherwise pass a fixed key like `wa-me`.
- Long runs: `tools.exec.timeoutSeconds` default 1800, `yieldMs` default 10000, then `process poll` (tools/exec.md).
- Alternative: `nodeHost.agentRuns.claude.enabled: true` on B (nodes/session-catalogs.md). Documented for the sessions catalog/Control UI; the docs don't say WhatsApp/Discord chats use it.

## Tested for real here (claude 2.1.306, authenticated sandbox)
- Prompt on stdin works with `-p`; JSON has `result`, `session_id`, `is_error`.
- `--resume <id>` keeps the same session id and remembers context, also from a different directory.
- A bad session id gives plain text (not JSON) and exit code 1; the script handles that.
- `claude-bridge.sh` end-to-end with the real CLI: first message, resume, corrupt-sid error.
- With a fake `claude`: failed first run leaves no sid file; sid saved only after success; stderr kept out of the JSON; chat-key validation; `auto` with and without context.
- Sandbox quirk: the first-run `session_id` equalled this sandbox's own session id (it inherits `CLAUDE_CODE_SESSION_ID`). Check on B that the first run creates a fresh id.

## NOT verified
- A real OpenClaw gateway, node pairing, allowlist matching of this script, or WhatsApp/Discord delivery. Nothing here ran against OpenClaw itself.
- `flock` locking was only smoke-tested (no failure, no proof of serialization). macOS lacks `flock` by default.
- `--resume` continues the conversation but does not type into a TUI open on B; two writers on one id can diverge.
- Headless runs cannot answer permission prompts; unlisted tools are denied. Avoid `bypassPermissions`.

## Setup
B: install `claude`, log in, copy the script, `openclaw node install --host <A> --port 18789 --display-name claude-b` (Tailscale/SSH tunnel if A's gateway is loopback-only). Set `BRIDGE_WORKDIR` to the project dir.
A: approve the node, run the `config set` and `allowlist add` commands above.

## Drive your existing session
Write that session's id into `~/.claude-bridge/<chat-key>.sid` (find ids under `~/.claude/projects/`). Cross-directory resume worked in my test, but set `BRIDGE_WORKDIR` to the original project dir to be safe. Avoid typing in the TUI at the same time.
