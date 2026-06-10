#!/usr/bin/env bash
# json.sh — JSON 파싱 헬퍼 (jq 의존)

ai_json_get() {
    local input="$1" path="$2" default="${3:-}"
    local result
    result=$(printf "%s" "$input" | jq -r "$path // empty" 2>/dev/null)
    printf "%s" "${result:-$default}"
}

ai_have_jq() {
    command -v jq >/dev/null 2>&1
}
