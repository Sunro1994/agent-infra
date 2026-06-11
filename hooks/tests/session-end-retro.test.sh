#!/usr/bin/env bash
# Test: session-end-retro.sh
set -e

INFRA_DIR="$(cd "$(dirname "$0")/../.." && pwd)"

# Test 1: corrections fixture → DRAFT 생성 + 새 섹션 포함
TMPDIR=$(mktemp -d)
TRANSCRIPT="$TMPDIR/transcript.jsonl"
cp "$(dirname "$0")/fixtures/transcript-corrections.jsonl" "$TRANSCRIPT"
INPUT_JSON="{\"session_id\":\"e2e-corr\",\"transcript_path\":\"$TRANSCRIPT\"}"

printf "%s" "$INPUT_JSON" | "$INFRA_DIR/hooks/session-end-retro.sh"

DRAFT=$(ls "$TMPDIR"/memory/feedback-retro-*-DRAFT.md 2>/dev/null | head -1)
if [ -z "$DRAFT" ]; then
    echo "FAIL: no DRAFT created for corrections fixture"
    exit 1
fi
if ! grep -q "## 🚨 사용자 정정" "$DRAFT"; then
    echo "FAIL: corrections section missing"
    exit 1
fi
echo "PASS: corrections e2e"
rm -rf "$TMPDIR"

# Test 2: clean fixture → DRAFT 생성 안 됨
TMPDIR=$(mktemp -d)
TRANSCRIPT="$TMPDIR/transcript.jsonl"
cp "$(dirname "$0")/fixtures/transcript-clean.jsonl" "$TRANSCRIPT"
INPUT_JSON="{\"session_id\":\"e2e-clean\",\"transcript_path\":\"$TRANSCRIPT\"}"

printf "%s" "$INPUT_JSON" | "$INFRA_DIR/hooks/session-end-retro.sh"

CLEAN_DRAFT=$(ls "$TMPDIR"/memory/feedback-retro-*-DRAFT.md 2>/dev/null | head -1)
if [ -n "$CLEAN_DRAFT" ]; then
    echo "FAIL: DRAFT created for clean fixture"
    exit 1
fi
echo "PASS: clean e2e (no DRAFT)"
rm -rf "$TMPDIR"
