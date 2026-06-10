#!/usr/bin/env bash
# precheck.sh — deploy-precheck 검사 로직
set +e

MODE="${1:-staged}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: not a git repo"; exit 2; }
cd "$ROOT"

# 대상 파일 산정
if [ "$MODE" = "all" ]; then
    FILES=$(git ls-files; git ls-files --others --exclude-standard)
else
    FILES=$(git diff --cached --name-only)
fi
FILES=$(echo "$FILES" | sort -u | grep -v '^$')

# ignore 패턴
IGNORE_FILE=".claude/deploy-precheck.ignore"
filter_ignored() {
    if [ -f "$IGNORE_FILE" ]; then
        grep -vFf "$IGNORE_FILE"
    else
        cat
    fi
}

FILES=$(echo "$FILES" | filter_ignored)

# 1. 토큰 자체 leak 방지
if echo "$FILES" | grep -qE '\.claude/\.deploy-token-'; then
    echo "CRITICAL: deploy token file is in commit candidates"
    exit 3
fi

# 2. 개인 문서 경로
PRIV_HITS=$(echo "$FILES" | grep -E '\.local\.md$|^plans/|^notes/|^scratch/' || true)

# 3. secret 파일 경로
SECRET_PATH_HITS=$(echo "$FILES" | grep -E '\.env$|\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|^secrets/|^credentials/' | grep -v '\.env\.example$' || true)

# 4. 내용 검사 — secret regex
SECRET_PATTERN='(API[_-]?KEY|SECRET[_-]?KEY|ACCESS[_-]?TOKEN|PRIVATE[_-]?KEY|PASSWORD|BEARER)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{12,}'
CONTENT_HITS=""
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    HIT=$(grep -nE "$SECRET_PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$HIT" ]; then
        CONTENT_HITS="$CONTENT_HITS\n$f:\n$HIT"
    fi
done <<< "$FILES"

# 종합
if [ -n "$PRIV_HITS$SECRET_PATH_HITS$CONTENT_HITS" ]; then
    echo "=== deploy-precheck: 차단됨 ==="
    [ -n "$PRIV_HITS" ] && { echo ""; echo "[개인 문서 경로]"; echo "$PRIV_HITS"; }
    [ -n "$SECRET_PATH_HITS" ] && { echo ""; echo "[Secret 파일 경로]"; echo "$SECRET_PATH_HITS"; }
    [ -n "$CONTENT_HITS" ] && { echo ""; echo "[하드코딩된 시크릿 패턴]"; echo -e "$CONTENT_HITS"; }
    echo ""
    echo "위 항목을 제거/이동/.gitignore 처리 후 재시도하세요."
    exit 1
fi

# 통과 → 토큰 생성
SHA=$(echo "$FILES" | shasum -a 256 | cut -c1-12)
mkdir -p .claude
TOKEN_FILE=".claude/.deploy-token-$SHA"
touch "$TOKEN_FILE"
echo "=== deploy-precheck: 통과 ==="
echo "토큰: $TOKEN_FILE (30분 유효)"
exit 0
