#!/usr/bin/env bash
# Test: session-end-retro.sh
set -e

INFRA_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="/tmp/agent-infra-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/memory"

# transcript 복사
cp "$(dirname "$0")/fixtures/transcript-with-patterns.jsonl" "$TEST_DIR/transcript.jsonl"

# input 작성 (transcript_path 절대경로)
INPUT='{"session_id":"test-session-001","transcript_path":"'$TEST_DIR/transcript.jsonl'"}'

# hook 실행
printf "%s" "$INPUT" | "$INFRA_DIR/hooks/session-end-retro.sh"

# DRAFT 파일 생성 확인
DRAFT=$(ls "$TEST_DIR/memory/"feedback-retro-*-DRAFT.md 2>/dev/null | head -1)
if [ -z "$DRAFT" ]; then
    echo "FAIL: DRAFT not created"
    exit 1
fi

# 내용 검증
if ! grep -q "duplicate_reads" "$DRAFT"; then
    echo "FAIL: duplicate_reads missing from draft"
    exit 1
fi

if ! grep -q "tool_errors: 3" "$DRAFT"; then
    echo "FAIL: tool_errors count missing"
    exit 1
fi

echo "PASS: session-end-retro.sh"
rm -rf "$TEST_DIR"
