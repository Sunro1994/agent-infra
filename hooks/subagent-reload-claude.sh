#!/usr/bin/env bash
# subagent-reload-claude.sh — SubagentStop: 메인에 CLAUDE.md 재확인 안내

set +e
export HOOK_NAME="subagent-reload-claude"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
AGENT=$(ai_json_get "$INPUT" '.agent_name' 'unknown')

ai_log "subagent ended: $AGENT"
printf "\n🔁 [agent-infra] sub-agent '%s' 종료. 다음 루프 시작 전 CLAUDE.md 정책을 재확인하세요.\n\n" "$AGENT" >&2
exit 0
