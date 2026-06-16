#!/usr/bin/env bash
# session-start-retro-alert.sh — 시작 시 직전 DRAFT 회고 목록 알림 + TTL 폐기

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

# TTL 폐기 — 30일 경과 DRAFT 자동 삭제 (AI_RETRO_TTL_DAYS로 override)
TTL_DAYS="${AI_RETRO_TTL_DAYS:-30}"
EXPIRED_COUNT=0
while IFS= read -r f; do
    [ -z "$f" ] && continue
    rm -f "$f"
    ai_log "TTL expired (>${TTL_DAYS}d): $(basename "$f")"
    EXPIRED_COUNT=$((EXPIRED_COUNT + 1))
done < <(find "$MEMORY_DIR" -maxdepth 1 -name "feedback-retro-*-DRAFT.md" -type f -mtime "+${TTL_DAYS}" 2>/dev/null)

DRAFTS=$(ls "$MEMORY_DIR"/feedback-retro-*-DRAFT.md 2>/dev/null || true)

if [ -z "$DRAFTS" ]; then
    if [ "$EXPIRED_COUNT" -gt 0 ]; then
        printf "\n[INFO] [agent-infra] TTL 만료로 %d개 자동 폐기됨 (>%d일), 잔여 DRAFT 없음\n\n" "$EXPIRED_COUNT" "$TTL_DAYS"
    fi
    ai_log "no DRAFT files (expired=$EXPIRED_COUNT)"
    exit 0
fi

COUNT=$(printf "%s\n" "$DRAFTS" | wc -l | tr -d ' ')

if [ "$COUNT" -ge 10 ]; then
    LEVEL="ALERT"
    SUFFIX=" — /retro-confirm 실행 권장 (누적 시급)"
elif [ "$COUNT" -ge 5 ]; then
    LEVEL="WARN"
    SUFFIX=" — /retro-confirm 으로 정리 권장"
else
    LEVEL="INFO"
    SUFFIX=":"
fi

printf "\n[%s] [agent-infra] 직전 세션 회고 초안 %d개%s\n" "$LEVEL" "$COUNT" "$SUFFIX"

if [ "$EXPIRED_COUNT" -gt 0 ]; then
    printf "        (TTL 만료로 %d개 자동 폐기됨, >%d일)\n" "$EXPIRED_COUNT" "$TTL_DAYS"
fi

# 5개 이하: 전체 목록. 5개 초과: 최신 3개 + "...외 N-3개"
if [ "$COUNT" -le 5 ]; then
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf "   - %s\n" "$(basename "$f")"
    done <<< "$DRAFTS"
else
    SORTED=$(printf "%s\n" "$DRAFTS" | sort -r)
    HEAD3=$(printf "%s\n" "$SORTED" | head -n 3)
    while IFS= read -r f; do
        [ -z "$f" ] && continue
        printf "   - %s\n" "$(basename "$f")"
    done <<< "$HEAD3"
    printf "   ... 외 %d개\n" "$((COUNT - 3))"
fi

printf "   /retro-confirm 으로 일괄 검토하세요.\n\n"
exit 0
