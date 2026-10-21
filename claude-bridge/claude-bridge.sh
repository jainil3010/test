#!/usr/bin/env bash
# Runs on machine B. Called by OpenClaw on machine A via `exec host=node`.
# Usage: claude-bridge.sh <chat-key> [--b64 <base64-message>]   (message on stdin otherwise)
#   <chat-key>  stable id for one phone conversation, e.g. whatsapp-1234 (letters, digits, - _ only)
# Env: BRIDGE_WORKDIR (project dir), BRIDGE_PERMISSION_MODE (default acceptEdits),
#      BRIDGE_ALLOWED_TOOLS (default "Read Grep Glob"), BRIDGE_STATE_DIR
set -euo pipefail

key="${1:?chat-key required}"; shift
[[ "$key" =~ ^[A-Za-z0-9_-]{1,64}$ ]] || { echo "bad chat-key" >&2; exit 2; }

if [[ "${1:-}" == "--b64" ]]; then
  msg="$(printf '%s' "${2:?base64 message required}" | base64 -d)"
else
  msg="$(cat)"
fi
[[ -n "$msg" ]] || { echo "empty message" >&2; exit 2; }

state="${BRIDGE_STATE_DIR:-$HOME/.claude-bridge}"
mkdir -p "$state"; chmod 700 "$state"
sid_file="$state/$key.sid"
cd "${BRIDGE_WORKDIR:-$HOME}"

args=(-p --output-format json
      --permission-mode "${BRIDGE_PERMISSION_MODE:-acceptEdits}"
      --allowedTools "${BRIDGE_ALLOWED_TOOLS:-Read Grep Glob}")

if [[ -s "$sid_file" ]]; then
  args+=(--resume "$(cat "$sid_file")")
else
  sid="$(python3 -c 'import uuid;print(uuid.uuid4())')"
  args+=(--session-id "$sid")
  printf '%s' "$sid" > "$sid_file"
fi

# message goes on stdin, never into a shell string
out="$(printf '%s' "$msg" | claude "${args[@]}")"
printf '%s' "$out" | python3 -c '
import json,sys
d=json.load(sys.stdin)
print(d.get("result",""))
sys.exit(1 if d.get("is_error") else 0)'
