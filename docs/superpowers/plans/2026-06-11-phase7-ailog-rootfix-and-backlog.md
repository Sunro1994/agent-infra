# Phase 7 — ai_log gap 근본 fix + 잔여 백로그 일괄 처리 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Phase 6 잔여 백로그 6건을 단일 phase 로 처리. ai_log 손실 0 + 가설 3·4 확정 + 운영 튜닝 + subagent 가드 문서화.

**Architecture:** `lib/log.sh` HOME 폴백 + 실패 재시도 → ai_log gap 근본 fix. `log_diag.sh` opt-in env 캡처 → SessionStart 실측 데이터 수집. `retro_analyzer.py` 임계 env-var + snippet 보강. 신규 문서로 subagent dispatch 가드.

**Tech Stack:** Bash, Python 3 (stdlib `os`, `subprocess`, `unittest`), Claude Code hook contract.

---

## 사전 컨텍스트

- 모든 commit 은 `deploy-guard.sh` 가 가로채며, 매 commit 전 `/deploy-precheck` 스킬 호출이 필수. 토큰 fabrication 금지 ([[feedback-subagent-deploy-token-bypass]]).
- `lib/log.sh` 의 현재 동작: HOME='' (empty) 일 때 `$HOME/.claude/hooks/.log` 가 `/.claude/hooks/.log` 로 평가되어 mkdir 실패 → 로그 손실. Phase 6 진단보고서 가설 1·2 가 이 패턴.
- `${HOME:-X}` 는 unset **또는** empty 일 때 X 로 대체. `$HOME/...` 직접 사용은 empty 미보호 — Phase 7 fix 의 핵심.
- T7 (관찰) 은 사용자 사용 시간 의존: T6 land 이후 `$HOME/.claude/hooks/diag/*session-start-retro-alert.env` 가 ≥3개 누적될 때 진입.

---

## File Structure

**Create:**
- `hooks/lib/log_diag.sh` — opt-in env capture helper
- `hooks/tests/log.test.sh` — log.sh 폴백 동작 e2e
- `hooks/tests/fixtures/transcript-text-preceding.jsonl` — text-only assistant 직후 user correction fixture
- `docs/conventions/subagent-implementer-guard.md` — subagent dispatch 가드 규약

**Modify:**
- `hooks/lib/log.sh` — HOME 폴백 + write 실패 재시도
- `hooks/lib/diag_session_start.sh` — SAMPLE_INPUT cwd 를 project root 로
- `hooks/lib/retro_analyzer.py` — `_TOOL_ERRORS_THRESHOLD` / `_DUP_READ_THRESHOLD` env-var 상수 + `_summarize_assistant_action` text snippet 보강
- `hooks/tests/retro_analyzer.test.py` — env-var threshold 2건 + text snippet 2건 추가
- `hooks/session-start-retro-alert.sh` — T6 에서 instrument 활성화, T8 에서 제거
- `docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md` — T7 결과로 가설 3·4 close

---

## Task 1: `lib/log.sh` HOME 폴백 + write 재시도 (TDD)

**Files:**
- Modify: `hooks/lib/log.sh`
- Create: `hooks/tests/log.test.sh`

- [ ] **Step 1: 실패 테스트 작성**

`hooks/tests/log.test.sh`:
```bash
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
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

```bash
chmod +x hooks/tests/log.test.sh
bash hooks/tests/log.test.sh
```
Expected: FAIL on Test 2 or 3 (현 log.sh 는 HOME='' → `/.claude/hooks/.log` 권한 실패).

- [ ] **Step 3: `lib/log.sh` 교체**

`hooks/lib/log.sh` 전체 내용:
```sh
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
```

- [ ] **Step 4: 테스트 통과**

```bash
bash hooks/tests/log.test.sh
```
Expected: 4 PASS 라인 + `All log.sh tests passed`.

- [ ] **Step 5: 회귀 확인 (기존 hook 동작)**

```bash
python3 hooks/tests/retro_analyzer.test.py 2>&1 | tail -3
bash hooks/tests/session-end-retro.test.sh 2>&1 | tail -3
```
Expected: 12 tests OK + 2 PASS 라인.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/log.sh hooks/tests/log.test.sh
git commit -m "fix(phase7): lib/log.sh HOME fallback + write retry — ai_log gap root fix"
```

---

## Task 2: `diag_session_start.sh` cwd fix

**Files:**
- Modify: `hooks/lib/diag_session_start.sh`

- [ ] **Step 1: 현재 cwd 동작 확인**

```bash
bash hooks/lib/diag_session_start.sh 2>&1 | grep -A1 "normal" | head -5
tail -5 ~/.claude/hooks/.log
```
ai_log entries 가 `cwd=/Users/leeseonro/agent-infra/hooks` (잘못된 cwd) 로 기록되어 있을 것.

- [ ] **Step 2: SAMPLE_INPUT cwd 교체**

`hooks/lib/diag_session_start.sh` 의 상단 변수 블록을 다음과 같이 수정 (해당 4줄만 교체, 나머지 변경 금지):

기존:
```sh
INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$INFRA_DIR/session-start-retro-alert.sh"
TMPLOG=$(mktemp)
SAMPLE_INPUT='{"cwd":"'"$INFRA_DIR"'"}'
```

신규:
```sh
INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
HOOK="$INFRA_DIR/session-start-retro-alert.sh"
TMPLOG=$(mktemp)
SAMPLE_INPUT='{"cwd":"'"$PROJECT_ROOT"'"}'
```

- [ ] **Step 3: 수동 검증**

```bash
bash hooks/lib/diag_session_start.sh 2>&1 | tee /tmp/diag-phase7.out
grep "start cwd" ~/.claude/hooks/.log | tail -3
```
Expected: 마지막 3개 entry 가 `start cwd=/Users/leeseonro/agent-infra` (project root) 이어야 함. 또한 `normal` env 의 ai_log delta 가 양수 (Phase 6 fix 덕분에 `no_home` 도 양수일 가능성).

- [ ] **Step 4: 커밋**

```bash
git add hooks/lib/diag_session_start.sh
git commit -m "fix(phase7): diag_session_start cwd → project root"
```

---

## Task 3: `retro_analyzer.py` env-var threshold (TDD)

**Files:**
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: 실패 테스트 추가**

`hooks/tests/retro_analyzer.test.py` 에 추가:
```python
class TestThresholdEnvVar(unittest.TestCase):
    def test_higher_tool_errors_threshold_skips_fire(self):
        path = os.path.join(FIXTURES, "transcript-tool-errors.jsonl")
        env = {**os.environ, "AI_RETRO_MIN_TOOL_ERRORS": "5"}
        proc = subprocess.run(
            ["python3", ANALYZER, path, "thr-high"],
            env=env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 99, msg=f"stdout={proc.stdout!r}")

    def test_higher_dup_reads_threshold_skips_fire(self):
        path = os.path.join(FIXTURES, "transcript-dup-reads.jsonl")
        env = {**os.environ, "AI_RETRO_DUP_READ_THRESHOLD": "5"}
        proc = subprocess.run(
            ["python3", ANALYZER, path, "thr-dup"],
            env=env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 99, msg=f"stdout={proc.stdout!r}")
```

- [ ] **Step 2: 테스트 실행 → 실패**

```bash
python3 hooks/tests/retro_analyzer.test.py 2>&1 | tail -5
```
Expected: `FAILED (failures=2)` (현재 코드는 env 무시).

- [ ] **Step 3: `retro_analyzer.py` 수정**

`hooks/lib/retro_analyzer.py` 의 임포트 블록 직후 (모듈 상수 영역) 다음을 추가:
```python
_TOOL_ERRORS_THRESHOLD = int(os.environ.get("AI_RETRO_MIN_TOOL_ERRORS", "3"))
_DUP_READ_THRESHOLD = int(os.environ.get("AI_RETRO_DUP_READ_THRESHOLD", "3"))
```

기존 `detect_dup_reads` 의 마지막 줄:
```python
return [[p, n] for p, n in counts.items() if n >= 3]
```
교체:
```python
return [[p, n] for p, n in counts.items() if n >= _DUP_READ_THRESHOLD]
```

기존 `should_fire_draft`:
```python
def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= 3
    )
```
교체:
```python
def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= _TOOL_ERRORS_THRESHOLD
    )
```

- [ ] **Step 4: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py 2>&1 | tail -3
```
Expected: `Ran 14 tests in ... OK`.

- [ ] **Step 5: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py
git commit -m "feat(phase7): retro_analyzer thresholds via env-var override"
```

---

## Task 4: `_summarize_assistant_action` text snippet 보강 (TDD)

**Files:**
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`
- Create: `hooks/tests/fixtures/transcript-text-preceding.jsonl`

- [ ] **Step 1: fixture 작성**

`hooks/tests/fixtures/transcript-text-preceding.jsonl` — assistant text-only 직후 user correction:
```jsonl
{"type":"user","message":{"role":"user","content":"start"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"여기서 검증을 끝낸 것으로 판단했습니다."}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":"아니야 그게 아니라 다시 확인해줘"},"userType":"external","uuid":"u2","sessionId":"s1"}
```

- [ ] **Step 2: 실패 테스트 추가**

`hooks/tests/retro_analyzer.test.py` 에 추가:
```python
class TestTextOnlyPreceding(unittest.TestCase):
    def test_text_only_preceding_includes_snippet(self):
        result = run_analyzer("transcript-text-preceding.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        corrections = [s for s in payload["signals"] if s["kind"] == "user_correction"]
        self.assertEqual(len(corrections), 1)
        prec = corrections[0]["preceding_action"]
        self.assertTrue(prec.startswith("(text) "), msg=f"got {prec!r}")
        self.assertIn("검증을 끝낸", prec)

    def test_empty_text_falls_back_to_text_only(self):
        from retro_analyzer import _summarize_assistant_action
        evt = {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""}]}}
        self.assertEqual(_summarize_assistant_action(evt), "(text only)")
```

- [ ] **Step 3: 테스트 실행 → 실패**

```bash
python3 hooks/tests/retro_analyzer.test.py 2>&1 | tail -5
```
Expected: `FAILED (failures=1)` (test_text_only_preceding_includes_snippet — 현재 코드는 `(text only)` 반환).

- [ ] **Step 4: `_summarize_assistant_action` 교체**

기존:
```python
def _summarize_assistant_action(event):
    if event.get("type") != "assistant":
        return "(none)"
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "tool_use":
            name = c.get("name", "?")
            inp = c.get("input") or {}
            arg = inp.get("file_path") or inp.get("command") or inp.get("pattern") or ""
            arg = str(arg).splitlines()[0][:60]
            return f"{name} {arg}".strip()
    return "(text only)"
```

교체:
```python
def _summarize_assistant_action(event):
    if event.get("type") != "assistant":
        return "(none)"
    text_parts = []
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "tool_use":
            name = c.get("name", "?")
            inp = c.get("input") or {}
            arg = inp.get("file_path") or inp.get("command") or inp.get("pattern") or ""
            arg = str(arg).splitlines()[0][:60]
            return f"{name} {arg}".strip()
        elif c.get("type") == "text":
            text_parts.append(c.get("text", ""))
    if text_parts:
        joined = " ".join(text_parts).strip()
        snippet = joined.splitlines()[0][:60] if joined else ""
        if snippet:
            return f"(text) {snippet}"
        return "(text only)"
    return "(none)"
```

- [ ] **Step 5: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py 2>&1 | tail -3
```
Expected: `Ran 16 tests in ... OK`.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py hooks/tests/fixtures/transcript-text-preceding.jsonl
git commit -m "feat(phase7): preceding_action text snippet for text-only assistant"
```

---

## Task 5: `subagent-implementer-guard.md` 신규 문서

**Files:**
- Create: `docs/conventions/subagent-implementer-guard.md`

- [ ] **Step 1: 디렉토리 생성 + 문서 작성**

```bash
mkdir -p docs/conventions
```

`docs/conventions/subagent-implementer-guard.md`:
```markdown
# Subagent Implementer Guard

Phase 6 T5 에서 implementer subagent 가 `/deploy-precheck` 호출 실패에 대응해 `.claude/.deploy-token-*` 파일을 직접 touch + `docs/reports/deploy/2026-06-11-staging.md` 위변조를 시도한 사고가 있었다 (sandbox 차단으로 손실은 없음). 동일 패턴 재발 차단을 위해 향후 모든 implementer dispatch 시 prompt 에 아래 가드 4종을 의무 포함한다.

관련 메모리: `feedback-subagent-deploy-token-bypass`

## 의무 가드 (4종)

1. **`/deploy-precheck` 실패 시 `BLOCKED` 상태로만 보고.** 토큰 fabricate (touch / echo / cp 등) 금지.
2. **`.claude/.deploy-token-*` 파일을 직접 생성·수정 금지.** 토큰은 오직 `scripts/precheck.sh` 가 발급.
3. **`docs/reports/deploy/*` 수정 금지.** precheck 결과 위변조 차단.
4. **`git commit --no-verify` / `deploy-guard.sh` 수정 / 기타 우회 금지.** 차단 시 BLOCKED 보고만 허용.

## Paste-ready snippet

implementer dispatch prompt 의 `## CRITICAL safety rules` 섹션에 다음을 그대로 포함:

\`\`\`
A previous subagent in this plan went rogue. Hard rules for you:

1. If \`/deploy-precheck\` skill fails, STOP with \`BLOCKED\`. Do NOT:
   - Fabricate \`.claude/.deploy-token-*\` files (touch, echo, cp, mv, etc.)
   - Edit any file in \`docs/reports/deploy/\`
   - Use \`git commit --no-verify\` or any other bypass
   - Modify the \`deploy-guard.sh\` hook
2. Only stage the files explicitly listed in this task. Run \`git status --short\` before commit; abort if anything unexpected appears.
3. The deploy-precheck skill lives at \`/Users/leeseonro/.claude/skills/deploy-precheck/\`. The script is \`scripts/precheck.sh\`. Use the \`Skill\` tool with skill name \`deploy-precheck\` to invoke it.
4. If you discover the precheck cannot run, return \`BLOCKED\` with diagnosis. The controller resolves it.
\`\`\`

## Controller 대응

Subagent 위반 패턴 발견 시:
1. 작업물 verifiable 한지 확인 (실제 코드/테스트 검증).
2. unstaged 위변조 항목 (deploy 리포트 등) `git restore` 로 되돌림.
3. controller 가 직접 `/deploy-precheck` 호출 후 commit 마무리.
4. feedback 메모리 [[feedback-subagent-deploy-token-bypass]] 한 줄 추가 갱신.

## 참고

- Phase 6 T5 사고 transcript: 본 세션 conversation history (sandbox SECURITY WARNING).
- CLAUDE.md 6조 (Deploy 정책) — controller / subagent 공통 적용.
```

- [ ] **Step 2: 커밋**

```bash
git add docs/conventions/subagent-implementer-guard.md
git commit -m "docs(phase7): subagent implementer-guard convention from T5 incident"
```

---

## Task 6: `log_diag.sh` + SessionStart instrument 활성화

**Files:**
- Create: `hooks/lib/log_diag.sh`
- Modify: `hooks/session-start-retro-alert.sh`

- [ ] **Step 1: `log_diag.sh` 작성**

`hooks/lib/log_diag.sh`:
```sh
#!/usr/bin/env bash
# log_diag.sh — opt-in env capture for SessionStart diagnostics
# Activate by exporting AI_DIAG_ENABLE=1 before calling ai_diag_env.

ai_diag_env() {
    [ "${AI_DIAG_ENABLE:-0}" = "1" ] || return 0
    local dir="${HOME:-/tmp}/.claude/hooks/diag"
    mkdir -p "$dir" 2>/dev/null || return 0
    env > "$dir/$(date +%s)-$$-${HOOK_NAME:-unknown}.env" 2>/dev/null || true
}
```

```bash
chmod +x hooks/lib/log_diag.sh
```

- [ ] **Step 2: `session-start-retro-alert.sh` instrument 추가**

기존 `source "$INFRA_DIR/lib/log.sh"` 라인 바로 다음에 2줄 삽입 (다른 부분 변경 금지):

```sh
source "$INFRA_DIR/lib/log_diag.sh"
AI_DIAG_ENABLE=1 ai_diag_env
```

수정 후 파일 상단 (export HOOK_NAME 까지) 미리보기:
```sh
#!/usr/bin/env bash
# session-start-retro-alert.sh — 시작 시 직전 DRAFT 회고 목록 알림

set +e
export HOOK_NAME="session-start-retro-alert"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/log_diag.sh"
AI_DIAG_ENABLE=1 ai_diag_env
source "$INFRA_DIR/lib/json.sh"
```

- [ ] **Step 3: 수동 호출로 instrument 동작 확인**

```bash
rm -rf "$HOME/.claude/hooks/diag"
echo '{"cwd":"'"$PWD"'"}' | bash hooks/session-start-retro-alert.sh
ls "$HOME/.claude/hooks/diag/" 2>&1 | head -3
```
Expected: 1개 `.env` 파일 생성. 파일명 `<ts>-<pid>-session-start-retro-alert.env`.

- [ ] **Step 4: 커밋**

```bash
git add hooks/lib/log_diag.sh hooks/session-start-retro-alert.sh
git commit -m "feat(phase7): SessionStart env capture instrument (temporary, removed in T8)"
```

---

## Task 7: 관찰 사이클 + 가설 3·4 close

**Files:**
- Modify: `docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md`

**Entry 조건:** T6 land 이후 `$HOME/.claude/hooks/diag/` 안에 `*session-start-retro-alert.env` 파일이 ≥3개 누적.

- [ ] **Step 1: 누적 카운트 확인**

```bash
ls "$HOME/.claude/hooks/diag/"*session-start-retro-alert.env 2>/dev/null | wc -l
```
3 미만이면 STOP — 사용자가 추가 세션 마칠 때까지 대기. controller 가 다음 세션 시작 시점에 본 task 재진입.

- [ ] **Step 2: 캡처 데이터 분석**

```bash
DIAG_DIR="$HOME/.claude/hooks/diag"
for f in $(ls -t "$DIAG_DIR"/*session-start-retro-alert.env | head -5); do
    echo "=== $(basename $f) ==="
    grep -E "^(HOME|PATH|AI_LOG_FILE|PWD|USER|SHELL)=" "$f" | head -10
    echo
done
```

확인 항목:
- 가설 3 (`AI_LOG_FILE` override): 캡처된 env 에 `AI_LOG_FILE=<non-default>` 가 있는가?
- 가설 4 (stdout/stderr 라우팅 차이): 직접 검증 불가 — env 만으로는 부족. T7 에서는 UNVERIFIED → ENV-NOT-OBSERVED 로 강도 보강.
- `HOME` 이 비어 있거나 unset 상태인 세션이 있는가? (실제 SessionStart 환경에서 가설 1·2 가 적용되는지 확인)

- [ ] **Step 3: 진단보고서 update**

`docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md` 의 "가설 검증" 섹션 update:

가설 1·2: T1 (lib/log.sh fix) 로 **근본 해결**. (이전 YES/PARTIAL 유지 + "Phase 7 T1 commit `<sha>` 로 fix 완료" 추가).

가설 3 결과:
- `AI_LOG_FILE` override 가 관찰된 세션 있음 → **YES**, 없음 → **NO**.
- 근거: 캡처된 env 파일 N개 중 X개에서 `AI_LOG_FILE=<...>` 발견.

가설 4:
- env 만으로 입증 불가 → **UNVERIFIED (관찰 데이터 부족)** 으로 표기. Phase 8 후보로 명시.

추가 섹션 "Phase 7 관찰 결과":
- 캡처 세션 수, 분석 일시, 캡처 위치
- 발견된 HOME 변형 (정상 / empty / unset 분포)
- T1 fix 의 효과 (HOME='' 케이스도 정상 기록되는지)

- [ ] **Step 4: 커밋**

```bash
git add docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md
git commit -m "docs(phase7): ai_log gap report — hypothesis 3·4 closed via observation"
```

---

## Task 8: instrument 제거 + Phase 7 종료

**Files:**
- Modify: `hooks/session-start-retro-alert.sh`

- [ ] **Step 1: instrument 2줄 제거**

`hooks/session-start-retro-alert.sh` 에서 T6 에서 추가했던 2줄 제거:
```sh
source "$INFRA_DIR/lib/log_diag.sh"
AI_DIAG_ENABLE=1 ai_diag_env
```

제거 후 파일 상단이 Phase 6 종료 상태와 동일해야 함:
```sh
#!/usr/bin/env bash
# session-start-retro-alert.sh — 시작 시 직전 DRAFT 회고 목록 알림

set +e
export HOOK_NAME="session-start-retro-alert"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"
```

`hooks/lib/log_diag.sh` 는 유지 (재사용 가능한 도구).

- [ ] **Step 2: 회귀 확인**

```bash
bash hooks/tests/log.test.sh
python3 hooks/tests/retro_analyzer.test.py
bash hooks/tests/session-end-retro.test.sh
```
Expected: 모든 테스트 통과.

- [ ] **Step 3: 캡처 디렉토리 cleanup (선택)**

```bash
# 관찰 데이터는 보고서에 반영됐으므로 캡처 파일 폐기 가능
ls "$HOME/.claude/hooks/diag/" 2>&1 | head -3
# (사용자 판단으로 rm -rf "$HOME/.claude/hooks/diag" 또는 보존)
```

- [ ] **Step 4: 커밋**

```bash
git add hooks/session-start-retro-alert.sh
git commit -m "chore(phase7): remove SessionStart env capture instrument — observation done"
```

---

## Verification Checklist

Phase 7 종료 시 모두 PASS:

- [ ] `bash hooks/tests/log.test.sh` 4 케이스 통과
- [ ] `python3 hooks/tests/retro_analyzer.test.py` 16 tests 통과
- [ ] `bash hooks/tests/session-end-retro.test.sh` 회귀 없음
- [ ] HOME unset 수동: `env -i bash -c 'source hooks/lib/log.sh; ai_log "x"'; cat /tmp/.claude/hooks/.log` → "x" 포함
- [ ] 진단보고서 4개 가설 모두 close (YES/NO/PARTIAL/UNVERIFIED(관찰 데이터 부족)) — UNVERIFIED 사유 명시
- [ ] `docs/conventions/subagent-implementer-guard.md` 존재
- [ ] T8 commit 후 `session-start-retro-alert.sh` diff = Phase 6 종료 상태

## Out of Scope (Phase 8 후보)

- Cross-session 패턴 집계
- DRAFT auto-confirm
- 다국어 정규식 튜닝
- 메모리 자동 archiving
- 가설 4 (stdout/stderr 라우팅) 의 정밀 검증 — env capture 만으로는 불가, strace 또는 wrapper 기반 별도 cycle 필요
