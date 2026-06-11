#!/usr/bin/env bash
# diag_session_start.sh — ai_log gap 재현 harness
# 사용: bash hooks/lib/diag_session_start.sh

set -u

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$INFRA_DIR/session-start-retro-alert.sh"
TMPLOG=$(mktemp)
SAMPLE_INPUT='{"cwd":"'"$INFRA_DIR"'"}'

run_env() {
    local label="$1"; shift
    echo "===== ENV: $label ====="

    local resolved
    resolved=$("$@" bash -c 'echo "$HOME"::"${AI_LOG_FILE:-$HOME/.claude/hooks/.log}"')
    echo "resolved: $resolved"

    local logfile="${HOME}/.claude/hooks/.log"
    local lines_before=0
    [ -f "$logfile" ] && lines_before=$(wc -l < "$logfile" | tr -d ' ')

    local stdout_capture stderr_capture exit_code
    set +e
    stdout_capture=$(printf '%s' "$SAMPLE_INPUT" | "$@" bash "$HOOK" 2>"$TMPLOG")
    exit_code=$?
    stderr_capture=$(cat "$TMPLOG")
    set -e

    local lines_after=0
    [ -f "$logfile" ] && lines_after=$(wc -l < "$logfile" | tr -d ' ')

    echo "exit: $exit_code"
    echo "stdout(${#stdout_capture}b): $stdout_capture" | head -c 300
    echo
    echo "stderr: $stderr_capture" | head -c 300
    echo
    echo "ai_log delta: $((lines_after - lines_before))"
    echo
}

run_env "normal" env
run_env "stripped" env -i HOME="$HOME" PATH="$PATH"
run_env "no_home" env -i PATH="$PATH"

rm -f "$TMPLOG"
