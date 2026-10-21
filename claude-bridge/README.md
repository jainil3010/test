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

## Setup: pair B as a node
All commands below come from the OpenClaw docs in the npm package (`gateway/pairing.md`, `cli/connect.md`, `nodes/node-host.md`, `nodes/pairing-and-status.md`). I have not run them against a real gateway.

**Before you start**
- B has `claude` installed and logged in, and `node` 20+/`npx` (assumed: needed for `npx openclaw`; check the OpenClaw install docs for the exact Node version).
- B can reach A's gateway (default port 18789). If A's gateway binds to loopback only, either set `gateway.publicOrigin` on A or open an SSH tunnel (see "Loopback gateway" below).
- Exec approvals on a node default to `full` with `ask: "off"`. Tighten them first if that's too broad: see `tools/exec-approvals.md`. This README's `tools.exec.mode allowlist` setting on A is a separate gate.

**Option 1: join code (recommended, one paste)**
1. On A, as an admin: `openclaw devices join-code`. It prints a URL like `https://<gateway>/j/<shortcode>`. The code is single-use and expires in about 10 minutes.
2. On B, run it as a command-only service node. Do **not** add `--session-host`; that lets B host full OpenClaw worker sessions, which you don't need:
   ```bash
   npx -y openclaw connect https://<gateway>/j/<shortcode> --service --display-name claude-b
   ```
   Leave off `--service` to run in the foreground first and watch it connect.
3. Docs say admin-minted join codes approve the device and its first command surface (including `system.run`) automatically. Confirm on A:
   ```bash
   openclaw nodes status
   openclaw nodes describe --node claude-b
   ```

**Option 2: manual pairing**
1. On B: `openclaw node install --host <A-host> --port 18789 --display-name claude-b` then `openclaw node start` (or `openclaw node run --host <A-host> --port 18789 --display-name claude-b` in the foreground). Auth uses `OPENCLAW_GATEWAY_TOKEN` or `OPENCLAW_GATEWAY_PASSWORD` in B's environment.
2. On A, approve the device, then the command surface. These are two separate request IDs:
   ```bash
   openclaw devices list
   openclaw devices approve <deviceRequestId>
   openclaw nodes pending
   openclaw nodes approve <nodeRequestId>
   openclaw nodes status
   ```
   Approving `system.run` needs `operator.pairing` + `operator.admin`. B retries with backoff (max 30s) while approval is pending; device requests expire 5 minutes after B's last retry.

**Loopback gateway (A binds to 127.0.0.1)**
```bash
# on B, keep running
ssh -N -L 18790:127.0.0.1:18789 user@<A-host>
# on B, another terminal
export OPENCLAW_GATEWAY_TOKEN="<gateway-token>"
openclaw node run --host 127.0.0.1 --port 18790 --display-name claude-b
```

**Reconnect later:** join codes are single-use. After the node stops, restart with `openclaw node restart` (service) or `openclaw node run` (foreground). Mint a new join code only to enroll again.

**Then route exec to B and allow the script (on A)**
```bash
openclaw config set tools.exec.host node
openclaw config set tools.exec.node "claude-b"
openclaw config set tools.exec.mode allowlist
openclaw approvals allowlist add --node claude-b "/abs/path/on/B/claude-bridge.sh"
```
Install the skill on B so A's agent learns the command: copy `skill/claude-bridge/` to `~/.openclaw/skills/claude-bridge/` on B, then `openclaw node restart` (node-hosted skills are not watched). Docs: the node must have `system.run` approved and the agent's exec policy must allow `host=node`, otherwise the skill is hidden from the agent.

**Smoke test (on A)**
```bash
openclaw nodes status                         # claude-b connected + paired
```
then, from WhatsApp/Discord, ask the agent to use the claude-bridge skill with a harmless prompt. Send me the exact error if anything fails.

## Drive your existing session
Write that session's id into `~/.claude-bridge/<chat-key>.sid` (find ids under `~/.claude/projects/`). Cross-directory resume worked in my test, but set `BRIDGE_WORKDIR` to the original project dir to be safe. Avoid typing in the TUI at the same time.
