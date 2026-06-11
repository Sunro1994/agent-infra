# Phase 7 — ai_log gap 근본 fix + 잔여 백로그 일괄 처리

작성일: 2026-06-11
상태: design (구현 대기)
이전 사이클: Phase 6 (`docs/superpowers/specs/2026-06-11-phase6-auto-retro-signal-and-ailog-gap-design.md`)

## 1. 배경

Phase 6 종료 시점에 final review 와 메모리에서 모은 백로그 6건을 단일 Phase 7 로 일괄 처리한다.

| # | 항목 | 출처 |
|---|---|---|
| 1 | `lib/log.sh` `mkdir -p` / `printf >>` 실패 처리 보강 — ai_log gap **근본 fix** | Phase 6 진단보고서 가설 1·2 |
| 2 | SessionStart 실제 env 캡처 instrumentation — 가설 3·4 검증 | Phase 6 진단보고서 |
| 3 | `diag_session_start.sh` cwd bug fix (INFRA_DIR → project root) | Phase 6 final review |
| 4 | `should_fire_draft` / `detect_dup_reads` 임계 env-var 오버라이드 | Phase 6 final review |
| 5 | `preceding_action: (text only)` 케이스에 assistant 텍스트 snippet 보강 | Phase 6 final review |
| 6 | subagent implementer-guard 규약 문서화 | [[feedback-subagent-deploy-token-bypass]] |

## 2. 목표

1. ai_log 손실을 0 건으로 만든다 — HOME unset / read-only filesystem 모두 폴백.
2. ai_log gap 4개 가설 모두 YES/NO/PARTIAL 로 확정 (UNVERIFIED 0).
3. retro_analyzer 운영 튜닝 (임계 env-var) + DRAFT 가독성 (text snippet) 보강.
4. 향후 subagent dispatch 의 deploy-token bypass 위험 차단 (문서화 가드).

### Non-goals

- Cross-session 패턴 집계, DRAFT auto-confirm, 다국어 정규식 튜닝.

## 3. 아키텍처

### 파일 구조

```
hooks/lib/
├── log.sh                        (MODIFY)
├── log_diag.sh                   (NEW: env capture helper, opt-in)
├── diag_session_start.sh         (MODIFY: cwd fix)
└── retro_analyzer.py             (MODIFY: env-var threshold + snippet 보강)

hooks/
└── session-start-retro-alert.sh  (MODIFY: 임시 instrument; Phase 7 종료 시 제거)

hooks/tests/
├── retro_analyzer.test.py        (MODIFY)
└── fixtures/
    └── transcript-text-preceding.jsonl   (NEW)

docs/
├── conventions/
│   └── subagent-implementer-guard.md     (NEW)
└── reports/diagnostics/
    └── 2026-06-11-ai-log-session-start-gap.md  (UPDATE)
```

### 컴포넌트 경계

- **`log.sh`**: 로깅 + 로그 파일 경로 결정. HOME unset / mkdir 실패 시 `/tmp` 폴백. `printf >>` 실패 시 동일 폴백 경로로 재시도.
- **`log_diag.sh`**: opt-in env 캡처 1개 함수만 노출. `AI_DIAG_ENABLE=1` 환경변수로 활성화. 활성 시 호출 1회당 `$HOME/.claude/hooks/diag/<ts>-<pid>-<hook>.env` 생성.
- **`retro_analyzer.py`**: 임계값 2개를 모듈 상수로 추출, `os.environ` 으로 오버라이드. `_summarize_assistant_action` 의 text-only 분기에 snippet 추가.
- **`session-start-retro-alert.sh`**: Phase 7 한정 instrument 라인 1줄 추가. Phase 7 종료 (T8) 시 제거.
- **`diag_session_start.sh`**: SAMPLE_INPUT 의 cwd 를 project root 로 변경.

## 4. 변경 명세

### 4.1 `lib/log.sh`

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

핵심:
- `${HOME:-/tmp}` 폴백.
- mkdir 실패 시 AI_LOG_FILE 자체를 `/tmp/ai_log.<uid>.log` 로 스왑.
- ai_log 의 append 실패 시 `/tmp/ai_log.fallback.log` 로 재시도.

### 4.2 `lib/log_diag.sh` (신규)

```sh
#!/usr/bin/env bash
# log_diag.sh — opt-in env capture for SessionStart diagnostics

ai_diag_env() {
    [ "${AI_DIAG_ENABLE:-0}" = "1" ] || return 0
    local dir="${HOME:-/tmp}/.claude/hooks/diag"
    mkdir -p "$dir" 2>/dev/null || return 0
    env > "$dir/$(date +%s)-$$-${HOOK_NAME:-unknown}.env" 2>/dev/null || true
}
```

### 4.3 `session-start-retro-alert.sh` — instrument 추가 (T6, T8 에서 제거)

기존 헤더 직후, `source "$INFRA_DIR/lib/log.sh"` 다음에 추가:
```sh
source "$INFRA_DIR/lib/log_diag.sh"
AI_DIAG_ENABLE=1 ai_diag_env
```

T8 종료 시 두 줄 모두 제거.

### 4.4 `diag_session_start.sh` cwd fix

```sh
INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
HOOK="$INFRA_DIR/session-start-retro-alert.sh"
TMPLOG=$(mktemp)
SAMPLE_INPUT='{"cwd":"'"$PROJECT_ROOT"'"}'
```

(INFRA_DIR 자체는 hook 경로 찾는 데 그대로 사용. SAMPLE_INPUT 의 cwd 만 PROJECT_ROOT 로 교체.)

### 4.5 `retro_analyzer.py` — env-var threshold

```py
_TOOL_ERRORS_THRESHOLD = int(os.environ.get("AI_RETRO_MIN_TOOL_ERRORS", "3"))
_DUP_READ_THRESHOLD = int(os.environ.get("AI_RETRO_DUP_READ_THRESHOLD", "3"))


def detect_dup_reads(events):
    ...
    return [[p, n] for p, n in counts.items() if n >= _DUP_READ_THRESHOLD]


def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= _TOOL_ERRORS_THRESHOLD
    )
```

상수 평가는 모듈 import 시점. 테스트는 subprocess 의 `env` 인자로 전달.

### 4.6 `retro_analyzer.py` — preceding_action snippet 보강

```py
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

규약:
- tool_use 가 하나라도 있으면 기존대로 `<Tool> <arg>` 반환 (tool_use 가 더 강한 시그널).
- text-only 인데 본문 0자 → `(text only)` 유지.
- text-only 본문 있음 → `(text) <≤60자 snippet>`.

### 4.7 `docs/conventions/subagent-implementer-guard.md` (신규)

내용:
- 향후 implementer dispatch 시 prompt 에 의무 포함할 가드 4종:
  1. `/deploy-precheck` 실패 시 `BLOCKED` 상태로만 보고. 토큰 fabricate 금지.
  2. `.claude/.deploy-token-*` 파일 직접 생성·수정 금지.
  3. `docs/reports/deploy/*` 수정 금지.
  4. `git commit --no-verify`, `deploy-guard.sh` 수정 등 우회 금지.
- 위반 패턴 발견 시 controller 가 즉시 rollback 절차.
- 참조: `feedback-subagent-deploy-token-bypass` 메모리, Phase 6 T5 사고 기록.
- 사용 예시 (paste-ready snippet) 포함.

## 5. Task 구성 (8개)

| T | 내용 | 산출물 |
|---|---|---|
| T1 | `lib/log.sh` HOME fallback + 실패 재시도 + 테스트 | `lib/log.sh`, `tests/log.test.sh` (신규) |
| T2 | `diag_session_start.sh` cwd fix + 수동 검증 | `lib/diag_session_start.sh` |
| T3 | `retro_analyzer.py` env-var threshold + 테스트 | `retro_analyzer.py`, `retro_analyzer.test.py` |
| T4 | `_summarize_assistant_action` text snippet + fixture + 테스트 | `retro_analyzer.py`, `transcript-text-preceding.jsonl`, `retro_analyzer.test.py` |
| T5 | `subagent-implementer-guard.md` 문서 | `docs/conventions/subagent-implementer-guard.md` |
| T6 | `log_diag.sh` 추가 + SessionStart instrument 활성화 | `lib/log_diag.sh`, `session-start-retro-alert.sh` |
| T7 | **관찰 사이클** — 사용자 ≥3 세션 사용 후 캡처된 `.env` 파일 분석 → 가설 3·4 판정 → 진단보고서 update | `docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md` |
| T8 | instrument 라인 제거 + Phase 7 종료 commit | `session-start-retro-alert.sh` |

T7 은 사용자 사용 시간 의존 task. 진입 조건은 구체적으로: T6 land 이후 `$HOME/.claude/hooks/diag/` 에 **`*session-start-retro-alert.env` 파일이 3 개 이상** 누적됐을 때. controller 가 ls 로 카운트해 만족 시 진입.

## 6. 테스트

### `lib/log.sh` (T1)
- 신규 `hooks/tests/log.test.sh` — 3개 시나리오:
  1. `HOME` 정상 → 정상 경로에 기록
  2. `HOME` unset → `/tmp/ai_log.<uid>.log` 에 기록
  3. mkdir 차단 (chmod 0000) → fallback 경로에 기록

### `retro_analyzer.py` (T3, T4)
- env-var threshold 4건:
  - 기본 (env 없음) → 기존 동작
  - `AI_RETRO_MIN_TOOL_ERRORS=1` → tool_errors=1 도 fire
  - `AI_RETRO_DUP_READ_THRESHOLD=2` → 2회 read 도 dup 으로
  - 둘 다 큰 값 → 일부러 fire 안 시킴
- snippet 보강 2건:
  - text-only 어시스턴트 → `(text) <snippet>` 반환
  - 빈 텍스트 어시스턴트 → `(text only)` 유지

총 신규 unit test: 4 (threshold) + 2 (snippet) = 6 → 12 (Phase 6) + 6 = 18 tests.

### diag harness (T2)
- 실행 후 ai_log delta 가 3 env 모두에서 양수인지 확인 (정상/stripped 는 양수, no_home 은 `lib/log.sh` 폴백으로 양수가 되어야 함 — T1 fix 의 부수 효과).

## 7. 마이그레이션 / 롤아웃

1. T1 land → 후속 task 가 새 `lib/log.sh` 위에서 동작.
2. T2~T5 land — 독립 변경.
3. T6 land → 다음 새 세션부터 env 캡처 시작.
4. T7 진입 조건: T6 land 이후 `$HOME/.claude/hooks/diag/*session-start-retro-alert.env` 파일이 ≥3개 누적.
5. T8 commit 후 Phase 7 종료. `feedback-subagent-deploy-token-bypass` 메모리 한 줄 갱신 — "implementer-guard.md 로 형식화 완료".

## 8. 성공 기준 (verifiable)

- [ ] `python3 hooks/tests/retro_analyzer.test.py` 18 개 모두 PASS
- [ ] `bash hooks/tests/log.test.sh` 3 케이스 모두 PASS
- [ ] `bash hooks/tests/session-end-retro.test.sh` 기존 케이스 회귀 없음
- [ ] HOME unset 수동 시나리오 (`env -i bash -c 'source hooks/lib/log.sh; ai_log "x"'`) → `/tmp/ai_log.<uid>.log` 에 기록 확인
- [ ] 진단보고서 4개 가설 UNVERIFIED 0 건 (T7 결과 반영)
- [ ] `docs/conventions/subagent-implementer-guard.md` 존재 + paste-ready snippet 포함
- [ ] instrument 라인 제거 commit (T8) 후 `session-start-retro-alert.sh` 가 Phase 6 종료 상태와 동일

## 9. Out of Scope (Phase 8 후보)

- Cross-session 패턴 집계 (DRAFT 들을 묶어 추세 분석)
- DRAFT auto-confirm (높은 confidence 시그널 자동 채택)
- 다국어 정규식 튜닝 (현재 ko/en)
- 메모리 자동 archiving (오래된 feedback memory 정리)
