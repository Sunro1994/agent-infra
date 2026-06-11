#!/usr/bin/env bash
# log_diag.sh — opt-in env capture for SessionStart diagnostics
# Activate by exporting AI_DIAG_ENABLE=1 before calling ai_diag_env.

ai_diag_env() {
    [ "${AI_DIAG_ENABLE:-0}" = "1" ] || return 0
    local dir="${HOME:-/tmp}/.claude/hooks/diag"
    mkdir -p "$dir" 2>/dev/null || return 0
    env > "$dir/$(date +%s)-$$-${HOOK_NAME:-unknown}.env" 2>/dev/null || true
}
