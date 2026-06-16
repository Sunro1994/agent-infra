#!/usr/bin/env bash
# session-start-retro-alert.test.sh
set -e
TEST_PROJ="/tmp/agent-infra-startup-test"
PROJECT_KEY=$(printf "%s" "$TEST_PROJ" | sed 's|/|-|g' | sed 's|^-||' | sed 's|^|-|')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"
HOOK="$(cd "$(dirname "$0")/.." && pwd)/session-start-retro-alert.sh"

cleanup() { rm -rf "$MEMORY_DIR" "$TEST_PROJ"; }
trap cleanup EXIT

reset() {
    rm -rf "$MEMORY_DIR" "$TEST_PROJ"
    mkdir -p "$TEST_PROJ" "$MEMORY_DIR"
}

run_hook() {
    local input='{"cwd":"'$TEST_PROJ'"}'
    printf "%s" "$input" | "$HOOK" 2>/dev/null
}

# Test 1: 2개 DRAFT → [INFO] 레벨
reset
touch "$MEMORY_DIR/feedback-retro-test1-DRAFT.md"
touch "$MEMORY_DIR/feedback-retro-test2-DRAFT.md"
OUT=$(run_hook)
if ! echo "$OUT" | grep -q "\[INFO\].*회고 초안 2개"; then
    echo "FAIL t1: INFO level missing for 2 drafts"
    echo "got: $OUT"
    exit 1
fi
echo "PASS t1: INFO level for low count"

# Test 2: 6개 DRAFT → [WARN] 레벨 + 요약 표시
reset
for i in 1 2 3 4 5 6; do touch "$MEMORY_DIR/feedback-retro-t${i}-DRAFT.md"; done
OUT=$(run_hook)
if ! echo "$OUT" | grep -q "\[WARN\].*회고 초안 6개"; then
    echo "FAIL t2: WARN level missing for 6 drafts"
    echo "got: $OUT"
    exit 1
fi
if ! echo "$OUT" | grep -q "외 3개"; then
    echo "FAIL t2: summary count missing"
    echo "got: $OUT"
    exit 1
fi
echo "PASS t2: WARN level + summary"

# Test 3: 10개 DRAFT → [ALERT] 레벨
reset
for i in $(seq 1 10); do touch "$MEMORY_DIR/feedback-retro-a${i}-DRAFT.md"; done
OUT=$(run_hook)
if ! echo "$OUT" | grep -q "\[ALERT\].*회고 초안 10개"; then
    echo "FAIL t3: ALERT level missing for 10 drafts"
    echo "got: $OUT"
    exit 1
fi
echo "PASS t3: ALERT level"

# Test 4: TTL 만료 — 31일 전 파일은 자동 폐기
reset
touch "$MEMORY_DIR/feedback-retro-old-DRAFT.md"
touch -t "$(date -v-31d +%Y%m%d%H%M.%S 2>/dev/null || date -d '31 days ago' +%Y%m%d%H%M.%S)" "$MEMORY_DIR/feedback-retro-old-DRAFT.md"
touch "$MEMORY_DIR/feedback-retro-new-DRAFT.md"
OUT=$(run_hook)
if [ -f "$MEMORY_DIR/feedback-retro-old-DRAFT.md" ]; then
    echo "FAIL t4: old DRAFT should be deleted"
    exit 1
fi
if [ ! -f "$MEMORY_DIR/feedback-retro-new-DRAFT.md" ]; then
    echo "FAIL t4: new DRAFT should NOT be deleted"
    exit 1
fi
if ! echo "$OUT" | grep -q "TTL 만료로 1개"; then
    echo "FAIL t4: TTL message missing"
    echo "got: $OUT"
    exit 1
fi
echo "PASS t4: TTL 31d expiry"

# Test 5: 모든 DRAFT가 TTL 만료 → DRAFT 0 + 알림만
reset
touch "$MEMORY_DIR/feedback-retro-only-DRAFT.md"
touch -t "$(date -v-40d +%Y%m%d%H%M.%S 2>/dev/null || date -d '40 days ago' +%Y%m%d%H%M.%S)" "$MEMORY_DIR/feedback-retro-only-DRAFT.md"
OUT=$(run_hook)
if [ -f "$MEMORY_DIR/feedback-retro-only-DRAFT.md" ]; then
    echo "FAIL t5: 40d-old DRAFT should be deleted"
    exit 1
fi
if ! echo "$OUT" | grep -q "TTL 만료로 1개"; then
    echo "FAIL t5: TTL-only message missing"
    echo "got: $OUT"
    exit 1
fi
echo "PASS t5: TTL-only path"

# Test 6: AI_RETRO_TTL_DAYS env override — 5일로 줄이면 7일 전 파일도 폐기
reset
touch "$MEMORY_DIR/feedback-retro-week-DRAFT.md"
touch -t "$(date -v-7d +%Y%m%d%H%M.%S 2>/dev/null || date -d '7 days ago' +%Y%m%d%H%M.%S)" "$MEMORY_DIR/feedback-retro-week-DRAFT.md"
OUT=$(AI_RETRO_TTL_DAYS=5 printf '{"cwd":"'$TEST_PROJ'"}' | AI_RETRO_TTL_DAYS=5 "$HOOK" 2>/dev/null)
if [ -f "$MEMORY_DIR/feedback-retro-week-DRAFT.md" ]; then
    echo "FAIL t6: TTL override should delete 7d-old DRAFT"
    exit 1
fi
echo "PASS t6: TTL env override"

echo "PASS: session-start-retro-alert.sh (6 tests)"
