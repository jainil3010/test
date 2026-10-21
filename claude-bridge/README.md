# Phone (C) → OpenClaw (A) → Claude Code (B)

WhatsApp/Discord message → OpenClaw gateway on A → `exec host=node` → `claude-bridge.sh` on B → `claude -p --resume`.

## Verified from OpenClaw docs (npm package openclaw@2026.10.5, docs/)
- A node host on B runs commands for the gateway on A: `openclaw node run --host <A> --port 18789` (nodes/node-host.md).
- Route exec to it: `openclaw config set tools.exec.host node`, `tools.exec.node "<name>"`, `tools.exec.mode allowlist` (nodes/node-exec.md).
- Allowlist on A: `openclaw approvals allowlist add --node <name> "/abs/path/claude-bridge.sh"` (nodes/node-exec.md).
- ACPX routes cannot dispatch to a paired device (nodes/node-host.md), so ACP alone would run Claude on A, not B.
- Long runs: `tools.exec.timeoutSeconds` default 1800; use `yieldMs`/`process poll` (tools/exec.md).
- Built-in alternative: `nodeHost.agentRuns.claude.enabled: true` on B makes Claude CLI sessions continuable from OpenClaw, using `claude -p` with `--fork-session` on the first turn (nodes/session-catalogs.md). It is documented for the Control UI sessions catalog; the docs do not say chat channels use it.

## Verified from `claude --help` (v2.1.306)
`-p`, `--output-format json`, `--resume <id>`, `--session-id <uuid>`, `--permission-mode` (acceptEdits|auto|bypassPermissions|manual|dontAsk|plan), `--allowedTools`.

## Tested
`claude-bridge.sh` logic (session create then resume, chat-key validation, base64 input, no shell interpolation of the message) tested against a **fake** `claude`. Not tested against a real model, real OpenClaw, or a real node.

## NOT verified, test on your machines
1. That `exec host=node` passes stdin to the script. If not, use `--b64`: `claude-bridge.sh wa-1 --b64 "$(printf %s "$MSG" | base64 -w0)"`.
2. That `claude -p` reads the prompt from stdin (expected, check on B).
3. `--resume` continues a conversation but does not type into a TUI already open on B. Running both on one session id can diverge.
4. Headless runs cannot answer permission prompts; unlisted tools are denied. Widen `BRIDGE_ALLOWED_TOOLS` deliberately; avoid `bypassPermissions`.

## Setup
B: install `claude` and log in; copy `claude-bridge.sh`; `openclaw node run --host <A> --port 18789 --display-name claude-b` (or `node install`). Use Tailscale or an SSH tunnel if A's gateway is loopback-only.
A: approve the node, then run the `config set` and `allowlist add` commands above. Give the OpenClaw agent an instruction to call the script with a per-chat key, passing the user's text only via stdin or `--b64`.
