#!/usr/bin/env bash
# session-end-retro.sh — 세션 종료 시 transcript 분석 → feedback 메모리 초안

set +e
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

ANALYSIS_JSON=$(python3 "$INFRA_DIR/lib/retro_analyzer.py" "$TRANSCRIPT_PATH" "$SESSION_ID" 2>>"$AI_LOG_FILE")
EXIT_CODE=$?

case "$EXIT_CODE" in
    99) ai_log "no significant patterns, skipping draft"; exit 0 ;;
    0)  ;;
    *)  ai_log "analyzer failed exit=$EXIT_CODE"; exit 0 ;;
esac

SLUG=$(date +"%Y%m%d-%H%M%S")
DRAFT_FILE="$MEMORY_DIR/feedback-retro-$SLUG-DRAFT.md"
printf '%s' "$ANALYSIS_JSON" | python3 "$INFRA_DIR/lib/retro_analyzer.py" --render > "$DRAFT_FILE"

ai_log "draft created: $DRAFT_FILE"
exit 0
