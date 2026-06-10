#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CLAUDE_DIR/_backups/agent-infra-$(date +%Y%m%d-%H%M%S)"

echo "==> agent-infra installer"
echo "    source: $INFRA_DIR"
echo "    target: $CLAUDE_DIR"
echo "    backup: $BACKUP_DIR"

# 1. 백업
mkdir -p "$BACKUP_DIR"
cp -r "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/" 2>/dev/null || true
echo "    [1/3] backed up settings.json + CLAUDE.md"

# 2. hooks/agents/skills symlink (Phase 2-5에서 실제 파일 추가됨)
for sub in hooks agents skills; do
    mkdir -p "$INFRA_DIR/$sub"
    if [ -L "$CLAUDE_DIR/$sub-infra" ]; then
        rm "$CLAUDE_DIR/$sub-infra"
    fi
    ln -s "$INFRA_DIR/$sub" "$CLAUDE_DIR/$sub-infra"
done
echo "    [2/3] symlinks: $CLAUDE_DIR/{hooks,agents,skills}-infra → $INFRA_DIR/{hooks,agents,skills}"

# 3. CLAUDE.md/settings.json 패치는 sentinel 라인 사이만 교체
# (실제 패치는 Phase 1 Task 1.5 에서 적용)
echo "    [3/3] CLAUDE.md/settings.json patch — Task 1.5에서 수동 적용"

echo "==> done"
