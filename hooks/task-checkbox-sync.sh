#!/usr/bin/env bash
# task-checkbox-sync.sh — PostToolUse(Edit/Write): 활성 [T-NNN] 토글

set +e
export HOOK_NAME="task-checkbox-sync"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
FILE=$(ai_json_get "$INPUT" '.tool_input.file_path' '')

if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then exit 0; fi
if [ -z "$FILE" ]; then exit 0; fi

# 프로젝트 루트 찾기 (git root, fallback: cwd)
ROOT=$(cd "$(dirname "$FILE")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# 활성 task ID 찾기: docs/plans/*.md 의 frontmatter active_task
ACTIVE_TASK=""
for plan in "$ROOT/docs/plans/"*.md; do
    [ -f "$plan" ] || continue
    ACTIVE_TASK=$(awk '/^---$/{n++; next} n==1 && /^active_task:/{gsub(/^active_task:[ ]*/,""); print; exit}' "$plan")
    [ -n "$ACTIVE_TASK" ] && break
done

if [ -z "$ACTIVE_TASK" ]; then
    ai_log "no active_task found, skip file=$FILE"
    exit 0
fi

# 활성 task ID로 TASK 파일 찾기
TASK_FILE=""
for tf in "$ROOT/docs/tasks/"*.md; do
    [ -f "$tf" ] || continue
    if grep -q "\[$ACTIVE_TASK\]" "$tf"; then TASK_FILE="$tf"; break; fi
done

if [ -z "$TASK_FILE" ]; then
    ai_log "active task $ACTIVE_TASK referenced but no TASK file contains it"
    exit 0
fi

# `- [ ] [T-NNN]` → `- [x] [T-NNN]`
TMP=$(mktemp)
sed "s/^\(- \[\) \(\] \[$ACTIVE_TASK\]\)/\1x\2/" "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"

ai_log "toggled $ACTIVE_TASK in $TASK_FILE"
exit 0
