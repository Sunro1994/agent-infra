#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

echo "==> agent-infra uninstaller"
for sub in hooks agents skills; do
    if [ -L "$CLAUDE_DIR/$sub-infra" ]; then
        rm "$CLAUDE_DIR/$sub-infra"
        echo "    removed symlink: $CLAUDE_DIR/$sub-infra"
    fi
done

LATEST_BACKUP=$(ls -td "$CLAUDE_DIR/_backups/agent-infra-"* 2>/dev/null | head -1 || true)
if [ -n "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP/settings.json" "$CLAUDE_DIR/" 2>/dev/null || true
    cp "$LATEST_BACKUP/CLAUDE.md" "$CLAUDE_DIR/" 2>/dev/null || true
    echo "    restored CLAUDE.md/settings.json from: $LATEST_BACKUP"
fi
echo "==> done"
