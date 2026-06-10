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

echo "PASS case 1 (flat repo)"
rm -rf "$SANDBOX"

# Case 2: nested sub-project — outer git repo without docs/plans, inner subdir with docs/plans (B-004)
SANDBOX2="/tmp/agent-infra-task-sync-test-nested"
rm -rf "$SANDBOX2"
mkdir -p "$SANDBOX2/sub/docs/plans" "$SANDBOX2/sub/docs/tasks" "$SANDBOX2/sub/src"
cd "$SANDBOX2"
git init -q  # outer repo. No docs/plans here.

cat > sub/docs/plans/feature.md <<'EOF'
---
title: 중첩 테스트
active_task: T-099
---
nested plan
EOF

cat > sub/docs/tasks/feature.md <<'EOF'
- [ ] [T-098] before
- [ ] [T-099] target
- [ ] [T-100] after
EOF

INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'$SANDBOX2/sub/src/foo.ts'"}}'
printf "%s" "$INPUT" | "$HOOK"

if ! grep -q '^\- \[x\] \[T-099\]' "$SANDBOX2/sub/docs/tasks/feature.md"; then
    echo "FAIL case 2: T-099 not toggled (B-004 regression — nested layout)"
    cat "$SANDBOX2/sub/docs/tasks/feature.md"
    exit 1
fi
if grep -q '^\- \[x\] \[T-098\]' "$SANDBOX2/sub/docs/tasks/feature.md"; then
    echo "FAIL case 2: T-098 incorrectly toggled"
    exit 1
fi
if grep -q '^\- \[x\] \[T-100\]' "$SANDBOX2/sub/docs/tasks/feature.md"; then
    echo "FAIL case 2: T-100 incorrectly toggled"
    exit 1
fi

echo "PASS case 2 (nested sub-project)"
rm -rf "$SANDBOX2"

echo "PASS: task-checkbox-sync.sh (2 cases)"
