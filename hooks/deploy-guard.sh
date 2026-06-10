#!/usr/bin/env bash
# deploy-guard.sh — PreToolUse(Bash): git commit/push 차단, deploy-precheck 토큰 검증

set +e
export HOOK_NAME="deploy-guard"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
CMD=$(ai_json_get "$INPUT" '.tool_input.command' '')

if [ "$TOOL" != "Bash" ]; then exit 0; fi

# git commit / git push 패턴 체크
if ! echo "$CMD" | grep -qE '\bgit\s+(commit|push)\b'; then
    exit 0
fi

ai_log "intercepted: $CMD"

# precheck 토큰 검증
ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$ROOT" ]; then
    DENY_REASON="현재 디렉토리가 git repo가 아닙니다."
else
    TOKEN_FILE=""
    for f in "$ROOT/.claude/.deploy-token-"*; do
        [ -f "$f" ] || continue
        # 30분 유효성
        AGE=$(($(date +%s) - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)))
        if [ "$AGE" -lt 1800 ]; then TOKEN_FILE="$f"; break; fi
    done
    if [ -n "$TOKEN_FILE" ]; then
        ai_log "token valid: $TOKEN_FILE"
        exit 0
    fi
    DENY_REASON="deploy-precheck 토큰이 없거나 만료됨. \`/deploy-precheck\` 스킬을 먼저 호출하세요."
fi

# permission deny 응답
jq -n --arg reason "$DENY_REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
