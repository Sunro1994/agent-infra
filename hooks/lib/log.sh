#!/usr/bin/env bash
# log.sh — agent-infra hooks 공통 로거
# usage: source "$(dirname "$0")/lib/log.sh" ; ai_log "message"

AI_LOG_FILE="${AI_LOG_FILE:-${HOME:-/tmp}/.claude/hooks/.log}"
AI_LOG_FALLBACK="/tmp/ai_log.$(id -u 2>/dev/null || echo 0).log"

if ! mkdir -p "$(dirname "$AI_LOG_FILE")" 2>/dev/null; then
    AI_LOG_FILE="$AI_LOG_FALLBACK"
    mkdir -p "$(dirname "$AI_LOG_FILE")" 2>/dev/null
fi

ai_log() {
    local hook_name="${HOOK_NAME:-unknown}"
    local timestamp
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    local line
    line=$(printf "[%s] [%s] %s\n" "$timestamp" "$hook_name" "$*")
    if ! printf "%s" "$line" >> "$AI_LOG_FILE" 2>/dev/null; then
        printf "%s" "$line" >> "$AI_LOG_FALLBACK" 2>/dev/null || true
    fi
}

ai_warn() {
    ai_log "WARN: $*"
    printf "%s\n" "$*" >&2
}
