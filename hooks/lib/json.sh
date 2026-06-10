#!/usr/bin/env bash
# json.sh — JSON 파싱 헬퍼 (jq 의존)

ai_json_get() {
    local input="$1"
    local path="$2"
    local default="${3:-}"
    printf "%s" "$input" | jq -r "$path // empty" 2>/dev/null || printf "%s" "$default"
}

ai_have_jq() {
    command -v jq >/dev/null 2>&1
}
