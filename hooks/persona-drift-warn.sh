#!/usr/bin/env bash
# persona-drift-warn.sh — UserPromptSubmit: 한 prompt에 다영역 키워드 혼재 시 페르소나 분리 권유

set +e
export HOOK_NAME="persona-drift-warn"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
PROMPT=$(ai_json_get "$INPUT" '.prompt' '')

if [ -z "$PROMPT" ]; then exit 0; fi

# 영역별 키워드
matches=()
echo "$PROMPT" | grep -qiE '기획|brainstorm|design|spec|prd' && matches+=("기획")
echo "$PROMPT" | grep -qiE '구현|implement|코드|작성|refactor' && matches+=("코드")
echo "$PROMPT" | grep -qiE 'qa|테스트|screenshot|playwright|버그리포트' && matches+=("QA")
echo "$PROMPT" | grep -qiE 'review|리뷰|의존성|트랜잭션|무결성' && matches+=("Review")
echo "$PROMPT" | grep -qiE 'deploy|배포|commit|push|환경변수' && matches+=("Deploy")

COUNT=${#matches[@]}
ai_log "matched persona=${matches[*]} count=$COUNT"

if [ "$COUNT" -ge 3 ]; then
    printf "\n🎭 [agent-infra] 이 prompt에 영역 %s가 섞여 있습니다: %s\n" "$COUNT개" "${matches[*]}"  >&2
    printf "   페르소나 단계별 분리를 권장합니다(기획→코드→QA→Review→Deploy).\n\n" >&2
fi

exit 0
