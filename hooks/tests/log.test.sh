#!/usr/bin/env bash
# Test: lib/log.sh — fallback paths
set -e

INFRA_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
LOG_LIB="$INFRA_DIR/hooks/lib/log.sh"

# Test 1: HOME set, normal write
TMPHOME=$(mktemp -d)
HOME="$TMPHOME" bash -c "source '$LOG_LIB'; ai_log 'test-normal'"
if ! grep -q "test-normal" "$TMPHOME/.claude/hooks/.log" 2>/dev/null; then
    echo "FAIL: normal HOME write"
    rm -rf "$TMPHOME"
    exit 1
fi
echo "PASS: normal HOME write"
rm -rf "$TMPHOME"

# Test 2: HOME empty → /tmp fallback path
EXPECTED="/tmp/.claude/hooks/.log"
rm -f "$EXPECTED"
HOME="" bash -c "source '$LOG_LIB'; ai_log 'test-empty-home'"
if ! grep -q "test-empty-home" "$EXPECTED" 2>/dev/null; then
    echo "FAIL: empty HOME → /tmp fallback"
    exit 1
fi
echo "PASS: empty HOME → /tmp fallback"

# Test 3: HOME unset → /tmp fallback path
rm -f "$EXPECTED"
env -i PATH="$PATH" bash -c "source '$LOG_LIB'; ai_log 'test-unset-home'"
if ! grep -q "test-unset-home" "$EXPECTED" 2>/dev/null; then
    echo "FAIL: unset HOME → /tmp fallback"
    exit 1
fi
echo "PASS: unset HOME → /tmp fallback"

# Test 4: read-only AI_LOG_FILE override → AI_LOG_FALLBACK
RO_DIR=$(mktemp -d)
chmod 0500 "$RO_DIR"
FALLBACK="/tmp/ai_log.$(id -u 2>/dev/null || echo 0).log"
rm -f "$FALLBACK"
AI_LOG_FILE="$RO_DIR/sub/log" bash -c "source '$LOG_LIB'; ai_log 'test-readonly'" 2>/dev/null
if ! grep -q "test-readonly" "$FALLBACK" 2>/dev/null; then
    echo "FAIL: read-only AI_LOG_FILE → fallback"
    chmod 0755 "$RO_DIR"; rm -rf "$RO_DIR"; rm -f "$FALLBACK"
    exit 1
fi
echo "PASS: read-only AI_LOG_FILE → fallback"
chmod 0755 "$RO_DIR"
rm -rf "$RO_DIR"
rm -f "$FALLBACK"

echo "All log.sh tests passed"
