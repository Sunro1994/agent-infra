#!/usr/bin/env bash
# doc-sprawl-warn.test.sh
set -e
TEST_DIR="/tmp/agent-infra-sprawl-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# 4개 md 생성 → 5번째 Write 시 경고
for i in 1 2 3 4; do touch "$TEST_DIR/a$i.md"; done

# 5번째 Write 이벤트
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_DIR/a5.md'"}}'
touch "$TEST_DIR/a5.md"

OUT=$(printf "%s" "$INPUT" | $(cd "$(dirname "$0")/.." && pwd)/doc-sprawl-warn.sh 2>&1)

if ! echo "$OUT" | grep -q "정리/그루핑"; then
    echo "FAIL: sprawl warning missing"
    rm -rf "$TEST_DIR"
    exit 1
fi

# 임계 미달 케이스: 단일 파일
TEST_DIR2="/tmp/agent-infra-sprawl-test2"
rm -rf "$TEST_DIR2"
mkdir -p "$TEST_DIR2"
touch "$TEST_DIR2/only.md"
INPUT2='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_DIR2/only.md'"}}'
OUT2=$(printf "%s" "$INPUT2" | $(cd "$(dirname "$0")/.." && pwd)/doc-sprawl-warn.sh 2>&1)

if echo "$OUT2" | grep -q "정리/그루핑"; then
    echo "FAIL: false positive on single-md dir"
    exit 1
fi

echo "PASS: doc-sprawl-warn.sh"
rm -rf "$TEST_DIR" "$TEST_DIR2"
