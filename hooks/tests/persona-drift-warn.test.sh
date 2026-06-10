#!/usr/bin/env bash
# persona-drift-warn.test.sh
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/persona-drift-warn.sh"

# Case 1: 단일 영역 → 경고 없음
OUT1=$(printf '{"prompt":"버그 좀 고쳐줘"}' | "$HOOK" 2>&1)
if echo "$OUT1" | grep -q "페르소나"; then
    echo "FAIL: false positive on single-domain prompt"
    exit 1
fi

# Case 2: 3 영역 혼재 → 경고
P='{"prompt":"기획부터 설계하고 코드 구현 후 QA까지 한 번에 처리해줘"}'
OUT2=$(printf "%s" "$P" | "$HOOK" 2>&1)
if ! echo "$OUT2" | grep -q "페르소나 단계별 분리"; then
    echo "FAIL: drift not detected"
    exit 1
fi

echo "PASS: persona-drift-warn.sh"
