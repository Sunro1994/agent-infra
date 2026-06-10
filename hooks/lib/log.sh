#!/usr/bin/env bash
# log.sh — agent-infra hooks 공통 로거
# usage: source "$(dirname "$0")/lib/log.sh" ; ai_log "message"

AI_LOG_FILE="${AI_LOG_FILE:-$HOME/.claude/hooks/.log}"
AI_LOG_DIR="$(dirname "$AI_LOG_FILE")"
mkdir -p "$AI_LOG_DIR"

ai_log() {
    local hook_name="${HOOK_NAME:-unknown}"
    local timestamp
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    printf "[%s] [%s] %s\n" "$timestamp" "$hook_name" "$*" >> "$AI_LOG_FILE"
}

ai_warn() {
    ai_log "WARN: $*"
    printf "%s\n" "$*" >&2
}
