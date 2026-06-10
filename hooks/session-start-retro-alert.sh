#!/usr/bin/env bash
# session-start-retro-alert.sh — 시작 시 직전 DRAFT 회고 목록 알림

set +e
export HOOK_NAME="session-start-retro-alert"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
CWD=$(ai_json_get "$INPUT" '.cwd' "$PWD")

ai_log "start cwd=$CWD"

# 메모리 디렉토리 찾기 (~/.claude/projects/<dir>/memory/)
PROJECT_KEY=$(printf "%s" "$CWD" | sed 's|/|-|g' | sed 's|^-||' | sed 's|^|-|')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"

if [ ! -d "$MEMORY_DIR" ]; then
    ai_log "no memory dir for project, skip"
    exit 0
fi

DRAFTS=$(ls "$MEMORY_DIR"/feedback-retro-*-DRAFT.md 2>/dev/null || true)

if [ -z "$DRAFTS" ]; then
    ai_log "no DRAFT files, skip"
    exit 0
fi

COUNT=$(printf "%s\n" "$DRAFTS" | wc -l | tr -d ' ')
printf "\n📋 [agent-infra] 직전 세션 회고 초안 %s개:\n" "$COUNT" >&2
while IFS= read -r f; do
    [ -z "$f" ] && continue
    printf "   - %s\n" "$(basename "$f")" >&2
done <<< "$DRAFTS"
printf "   확정/폐기는 해당 파일을 직접 편집하세요.\n\n" >&2

exit 0
