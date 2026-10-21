#!/usr/bin/env bash
# Runs on machine B. OpenClaw on A calls it via `exec host=node`.
# Usage: claude-bridge.sh <chat-key|auto> [-- <message...>]   (message on stdin if none given)
#   chat-key  one id per phone conversation: letters, digits, - _ (max 64)
#   auto      derive from $OPENCLAW_CHANNEL_CONTEXT (JSON with chatId); see README (untested)
# Env: BRIDGE_WORKDIR (default $HOME), BRIDGE_PERMISSION_MODE (default acceptEdits),
#      BRIDGE_ALLOWED_TOOLS (default "Read Grep Glob"), BRIDGE_STATE_DIR (default ~/.claude-bridge)
# Needs: claude, python3, flock (Linux; on macOS install util-linux or drop the lock).
set -uo pipefail
fail() { echo "bridge error: $1"; exit "${2:-1}"; }

key="${1:-}"; [[ -n "$key" ]] || fail "chat-key required" 2; shift
if [[ "$key" == auto ]]; then
  key="$(python3 -c 'import json,os,re;c=json.loads(os.environ["OPENCLAW_CHANNEL_CONTEXT"]);print(re.sub(r"[^A-Za-z0-9_-]","_",str(c["chatId"]))[:64])' 2>/dev/null)" \
    || fail "auto: OPENCLAW_CHANNEL_CONTEXT missing or has no chatId" 2
fi
[[ "$key" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || fail "bad chat-key" 2

[[ "${1:-}" == -- ]] && shift
if [[ $# -gt 0 ]]; then msg="$*"; else msg="$(cat)"; fi
[[ -n "$msg" ]] || fail "empty message" 2

state="${BRIDGE_STATE_DIR:-$HOME/.claude-bridge}"
mkdir -p "$state" && chmod 700 "$state"
sid_file="$state/$key.sid"
cd "${BRIDGE_WORKDIR:-$HOME}" || fail "BRIDGE_WORKDIR not found" 2

exec 9>"$state/$key.lock"
flock 9   # one message per chat at a time

args=(-p --output-format json
      --permission-mode "${BRIDGE_PERMISSION_MODE:-acceptEdits}"
      --allowedTools "${BRIDGE_ALLOWED_TOOLS:-Read Grep Glob}")
[[ -s "$sid_file" ]] && args+=(--resume "$(cat "$sid_file")")

errf="$(mktemp)"; trap 'rm -f "$errf"' EXIT
out="$(printf '%s' "$msg" | claude "${args[@]}" 2>"$errf")"; rc=$?
[[ -n "$out" ]] || out="$(head -c 500 "$errf")"
# claude prints plain text (not JSON) on some errors, e.g. unknown session id
parsed="$(printf '%s' "$out" | python3 -c '
import json,sys
d=json.loads(sys.stdin.read())
print(d.get("session_id",""))
print("1" if d.get("is_error") else "0")
print(d.get("result",""))' 2>/dev/null)" || fail "claude failed (rc=$rc): ${out:0:500}"
sid="$(sed -n 1p <<<"$parsed")"; is_err="$(sed -n 2p <<<"$parsed")"; result="$(sed -n '3,$p' <<<"$parsed")"
[[ "$is_err" == 0 && $rc -eq 0 ]] || fail "claude reported error: $result"
[[ -n "$sid" ]] && printf '%s' "$sid" > "$sid_file"   # saved only after success
printf '%s\n' "$result"
