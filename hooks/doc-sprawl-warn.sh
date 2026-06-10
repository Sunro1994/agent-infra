#!/usr/bin/env bash
# doc-sprawl-warn.sh — PostToolUse(Write): 같은 dir에 md 5개 이상이면 정리 권유

set +e
export HOOK_NAME="doc-sprawl-warn"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

THRESHOLD="${AI_DOC_SPRAWL_THRESHOLD:-5}"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
FILE=$(ai_json_get "$INPUT" '.tool_input.file_path' '')

ai_log "tool=$TOOL file=$FILE"

# Write만, md만
if [ "$TOOL" != "Write" ]; then exit 0; fi
case "$FILE" in
    *.md|*.markdown) ;;
    *) exit 0 ;;
esac

DIR=$(dirname "$FILE")
COUNT=$(find "$DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "$COUNT" -ge "$THRESHOLD" ]; then
    printf "\n📁 [agent-infra] %s 에 .md 파일이 %s개 누적되었습니다. 정리/그루핑을 고려하세요.\n\n" "$DIR" "$COUNT" >&2
    ai_log "sprawl detected: dir=$DIR count=$COUNT"
fi

exit 0
