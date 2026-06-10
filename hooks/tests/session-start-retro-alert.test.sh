#!/usr/bin/env bash
# session-start-retro-alert.test.sh
set -e
TEST_PROJ="/tmp/agent-infra-startup-test"
PROJECT_KEY=$(printf "%s" "$TEST_PROJ" | sed 's|/|-|g' | sed 's|^-||' | sed 's|^|-|')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"

mkdir -p "$TEST_PROJ"
mkdir -p "$MEMORY_DIR"
touch "$MEMORY_DIR/feedback-retro-test1-DRAFT.md"
touch "$MEMORY_DIR/feedback-retro-test2-DRAFT.md"

INPUT='{"cwd":"'$TEST_PROJ'"}'
OUT=$(printf "%s" "$INPUT" | $(cd "$(dirname "$0")/.." && pwd)/session-start-retro-alert.sh 2>&1 >/dev/null)

if ! echo "$OUT" | grep -q "회고 초안 2개"; then
    echo "FAIL: alert message missing"
    rm -rf "$MEMORY_DIR" "$TEST_PROJ"
    exit 1
fi

echo "PASS: session-start-retro-alert.sh"
rm -rf "$MEMORY_DIR" "$TEST_PROJ"
