#!/usr/bin/env bash
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/deploy-guard.sh"
SANDBOX="/tmp/agent-infra-deploy-guard-test"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/.claude"
cd "$SANDBOX"
git init -q

# Case 1: 토큰 없음 → deny
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}' | "$HOOK")
if ! echo "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL: should deny without token"
    echo "$OUT"
    exit 1
fi

# Case 2: 유효한 토큰 → 통과 (출력 없음)
touch "$SANDBOX/.claude/.deploy-token-abc123"
OUT2=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}' | "$HOOK")
if [ -n "$OUT2" ]; then
    echo "FAIL: should be silent with valid token (got: $OUT2)"
    exit 1
fi

# Case 3: git status는 통과 (commit/push 아님)
OUT3=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | "$HOOK")
if [ -n "$OUT3" ]; then
    echo "FAIL: git status should not be blocked"
    exit 1
fi

# Case 4: 만료된 토큰 (31분 전 mtime)
rm "$SANDBOX/.claude/.deploy-token-abc123"
touch -t "$(date -v-31M +%Y%m%d%H%M)" "$SANDBOX/.claude/.deploy-token-old" 2>/dev/null || \
  touch -d "31 minutes ago" "$SANDBOX/.claude/.deploy-token-old"
OUT4=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | "$HOOK")
if ! echo "$OUT4" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL: expired token should still deny"
    exit 1
fi

echo "PASS: deploy-guard.sh"
rm -rf "$SANDBOX"
