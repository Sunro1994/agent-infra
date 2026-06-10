#!/usr/bin/env bash
# session-end-retro.sh — 세션 종료 시 transcript 정량 분석 → feedback 메모리 초안

set +e  # silent fail
export HOOK_NAME="session-end-retro"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
SESSION_ID=$(ai_json_get "$INPUT" '.session_id' 'unknown')
TRANSCRIPT_PATH=$(ai_json_get "$INPUT" '.transcript_path' '')

ai_log "start session_id=$SESSION_ID transcript=$TRANSCRIPT_PATH"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    ai_log "no transcript, skipping"
    exit 0
fi

PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
MEMORY_DIR="$PROJECT_DIR/memory"
mkdir -p "$MEMORY_DIR"

# 정량 분석: jsonl 파싱
PY_SCRIPT=$(cat <<'PYEOF'
import json, sys, re
from collections import Counter

transcript = sys.argv[1]
session_id = sys.argv[2]

read_files = Counter()
tool_errors = 0
verify_keywords = 0

with open(transcript) as f:
    for line in f:
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue
        tool = evt.get('tool_name') or evt.get('toolName')
        if tool == 'Read':
            path = (evt.get('tool_input') or {}).get('file_path')
            if path:
                read_files[path] += 1
        if evt.get('error') or evt.get('is_error'):
            tool_errors += 1
        text = json.dumps(evt)
        verify_keywords += len(re.findall(r'\b(verified|verifying|verify)\b', text, re.I))

dup_reads = [(f, n) for f, n in read_files.items() if n >= 3]
if not dup_reads and tool_errors < 3 and verify_keywords < 1:
    sys.exit(99)  # 임팩트 없음

print(f"session: {session_id}")
print(f"duplicate_reads: {dup_reads}")
print(f"tool_errors: {tool_errors}")
print(f"verify_keywords: {verify_keywords}")
PYEOF
)

ANALYSIS=$(python3 -c "$PY_SCRIPT" "$TRANSCRIPT_PATH" "$SESSION_ID" 2>>"$AI_LOG_FILE")
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 99 ]; then
    ai_log "no significant patterns, skipping draft"
    exit 0
fi

if [ "$EXIT_CODE" -ne 0 ]; then
    ai_log "python analysis failed"
    exit 0
fi

# DRAFT 메모리 생성
SLUG=$(date +"%Y%m%d-%H%M%S")
DRAFT_FILE="$MEMORY_DIR/feedback-retro-$SLUG-DRAFT.md"

cat > "$DRAFT_FILE" <<EOF
---
name: feedback-retro-$SLUG
description: "세션 자동 회고 초안 — 사용자 검토 후 확정/폐기"
metadata:
  type: feedback
  status: draft
  session_id: $SESSION_ID
---

# 자동 회고 초안

다음 패턴이 이번 세션에서 감지되었습니다. 의미 있는 신호인지 검토 후 확정/폐기하세요.

$ANALYSIS

**다음 액션**:
- 확정 시: 이 파일에서 \`-DRAFT\` 제거하고 MEMORY.md 인덱스에 추가
- 폐기 시: 이 파일 삭제
EOF

ai_log "draft created: $DRAFT_FILE"
exit 0
