#!/usr/bin/env bash
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/subagent-reload-claude.sh"
OUT=$(printf '{"agent_name":"qa-agent"}' | "$HOOK" 2>&1)
if ! echo "$OUT" | grep -q "qa-agent"; then
    echo "FAIL: agent name not in output"
    exit 1
fi
if ! echo "$OUT" | grep -q "CLAUDE.md"; then
    echo "FAIL: CLAUDE.md mention missing"
    exit 1
fi
echo "PASS: subagent-reload-claude.sh"
