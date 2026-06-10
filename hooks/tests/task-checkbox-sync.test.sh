#!/usr/bin/env bash
# task-checkbox-sync.test.sh
set -e

HOOK="$(cd "$(dirname "$0")/.." && pwd)/task-checkbox-sync.sh"
SANDBOX="/tmp/agent-infra-task-sync-test"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/docs/plans" "$SANDBOX/docs/tasks" "$SANDBOX/src"
cd "$SANDBOX"
git init -q

cat > docs/plans/feature.md <<'EOF'
---
title: 테스트
active_task: T-042
---
plan body
EOF

cat > docs/tasks/feature.md <<'EOF'
- [ ] [T-041] 이미 끝낸 것
- [ ] [T-042] 활성 작업
- [ ] [T-043] 다음 작업
EOF

# Edit 이벤트 시뮬레이션
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'$SANDBOX/src/foo.ts'"}}'
printf "%s" "$INPUT" | "$HOOK"

# 결과 확인
if ! grep -q '^\- \[x\] \[T-042\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-042 not toggled to [x]"
    cat "$SANDBOX/docs/tasks/feature.md"
    exit 1
fi

# T-041 / T-043 은 변경 없어야 함
if grep -q '^\- \[x\] \[T-041\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-041 incorrectly toggled"
    exit 1
fi
if grep -q '^\- \[x\] \[T-043\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-043 incorrectly toggled"
    exit 1
fi

echo "PASS: task-checkbox-sync.sh"
rm -rf "$SANDBOX"
