# Phase 6 — auto-retro 신호 강화 + ai_log gap 진단

작성일: 2026-06-11
상태: design (구현 대기)

## 1. 배경

Phase 5 종료 시점에 두 가지 별건이 백로그로 분리됐다.

- **auto-retro 신호 약함**: `hooks/session-end-retro.sh` 가 매 세션 종료마다 DRAFT 회고를 생성하지만, 출력 시그널이 카운트 metric 3종(`duplicate_reads`, `tool_errors`, `verify_keywords`)에 그쳐 사용자가 확정/폐기 판단을 내릴 컨텍스트가 부족하다. 2026-06-10~11 사이 생성된 DRAFT 8건 전부 폐기됐다 (confirmed → MEMORY.md 진입 비율 **0/8**). 원인은 `verify_keywords < 1` 이 fire-trigger 임계에 들어 있어 거의 모든 세션이 DRAFT 를 생성하기 때문.
- **ai_log gap**: Phase 5 진단 도중, 일부 SessionStart:startup 실행이 transcript attachment 상에는 hook 실행 기록을 남기지만 `~/.claude/hooks/.log` 엔 해당 entry 가 누락되는 케이스가 발견됐다. 재현 조건이 미확정.

Phase 6 는 두 별건을 한 spec 으로 묶되, 사이클은 분리한다.

## 2. 목표

1. auto-retro DRAFT 의 **탐지 정확도 향상** — 의미있는 패턴이 있는 세션에서만 DRAFT 가 생기게 한다. 사용자 확정/폐기 판단 비용을 30초 내로 줄인다.
2. ai_log gap 의 **재현 조건 규명** — 어떤 SessionStart 환경에서 로그 누락이 일어나는지 보고서로 정리한다. **수정은 Phase 6 범위 밖**.

### Non-goals

- ai_log gap 의 근본 수정 (별도 사이클)
- DRAFT auto-confirm 로직 (사용자 게이팅은 유지)
- 크로스-세션 패턴 집계 (multi-DRAFT correlation)
- 한국어/영어 외 다국어 패턴 튜닝

## 3. 아키텍처

### 파일 구조

```
hooks/
├── session-end-retro.sh              (수정: slim wrapper, JSON 수신 → DRAFT 렌더)
├── lib/
│   ├── retro_analyzer.py             (신규: signal extraction 모듈)
│   └── diag_session_start.sh         (신규: ai_log gap 재현 harness)
└── tests/
    ├── session-end-retro.test.sh     (수정: 새 DRAFT 섹션 assert)
    ├── retro_analyzer.test.py        (신규: fixture 단위테스트)
    └── fixtures/
        ├── transcript-corrections.jsonl
        ├── transcript-verify-then-change.jsonl
        ├── transcript-dup-reads.jsonl
        └── transcript-clean.jsonl

docs/reports/diagnostics/
└── YYYY-MM-DD-ai-log-session-start-gap.md   (신규: 재현 보고서, 작성일 기준 파일명)
```

### 컴포넌트 경계

- **session-end-retro.sh**: 입력 파싱(JSON stdin) → `retro_analyzer.py` 실행 → 결과 JSON 을 DRAFT 마크다운으로 렌더 → 파일 저장. **시그널 판정 로직 미포함**.
- **retro_analyzer.py**: transcript 단독 분석. 셸 의존 없음. 표준출력으로 JSON 만 반환. exit code 로 fire/skip 신호 (`0`=fire, `99`=no signal, 그 외=에러).
- **diag_session_start.sh**: 별도 명령. 평소 hook 흐름과 무관. 수동 실행으로 ai_log gap 재현 시도.
- **retro_analyzer.test.py**: python `unittest`. fixture 기반.
- **session-end-retro.test.sh**: 기존 그대로 end-to-end 검증. 새 DRAFT 섹션 출현 assertion 추가.

## 4. retro_analyzer.py 명세

### 호출 규약

```
python3 hooks/lib/retro_analyzer.py <transcript_path> <session_id>
```

표준출력: 시그널 있을 시 JSON. exit 99 일 때는 출력 없음.
표준에러: 진단 메시지 (셸이 `AI_LOG_FILE` 로 append).

### 출력 JSON 스키마

```json
{
  "session_id": "<id>",
  "metrics": {
    "duplicate_reads": [["<path>", 3]],
    "tool_errors": 0,
    "verify_keywords": 21
  },
  "signals": [
    {
      "kind": "user_correction",
      "turn_index": 47,
      "quote": "<≤120자 trim>",
      "preceding_action": "Edit hooks/foo.sh"
    },
    {
      "kind": "verify_then_change",
      "file": "hooks/foo.sh",
      "verify_turn": 51,
      "change_turn": 53,
      "verify_quote": "<≤120자 trim>",
      "change_quote": "Edit hooks/foo.sh"
    }
  ]
}
```

### 함수 분리

| 함수 | 책임 |
|---|---|
| `parse_events(path)` | jsonl 라인 단위 파싱, malformed 무시 |
| `detect_user_corrections(events) -> list[Signal]` | (a) 신호 |
| `detect_verify_then_change(events) -> list[Signal]` | (b) 신호 |
| `detect_dup_reads(events) -> list[(path, count)]` | path별 Read ≥3회 |
| `count_tool_errors(events) -> int` | `error` 또는 `is_error` true |
| `count_verify_keywords(events) -> int` | 지표 전용 (fire 트리거 아님) |
| `should_fire_draft(metrics, signals) -> bool` | 최종 임계 판정 |
| `main()` | 위 함수 조합, JSON dump, exit code 결정 |

### Signal 정의

**(a) user_correction**

- 대상 이벤트: `role: "user"` && 본문이 실제 사용자 입력 (tool_result, system-reminder 텍스트는 제외)
- 패턴(case-insensitive):
  ```
  \b(아니야|아니라|그게\s*아니|틀렸|잘못|다시|되돌|revert|undo|stop|wait|not\s+what|wrong|incorrect)\b
  ```
  + `미안.*취소` 형태의 한국어 양보+철회 패턴 1종 추가.
- 1건 이상 매칭 → 시그널 발화
- evidence 수집:
  - `turn_index`: 매칭 발생 event 의 시퀀셜 인덱스 (0-based, jsonl 라인 순서)
  - `quote`: 매칭 줄 원문. 길이 ≤120자면 그대로, 초과 시 매칭 부분 중심으로 trim 하고 trim 된 쪽에만 `…` 추가
  - `preceding_action`: 직전 assistant event 의 첫 tool_use 를 `<ToolName> <file_path or first arg>` 형태로 (예: `Edit hooks/foo.sh`). 직전 assistant 가 text-only 면 `(text only)`. 직전이 없으면 `(none)`

**(b) verify_then_change**

- 트리거 이벤트: `role: "assistant"` 텍스트에서 다음 패턴 매칭
  ```
  \b(verified|verifying|passing\s*now|passes\s*now|fixed|complete|works\s*now|confirmed)\b
  ```
- 트리거 이후 **같은 세션에서 ≤5 events 이내** (role 무관, jsonl 라인 카운트) 동일 파일에 대한 `Edit` 또는 `Write` tool_use 발생 시 시그널.
- 동일 파일 판정: `os.path.realpath` 로 정규화 후 일치. 상대경로면 transcript 가 위치한 디렉토리 기준 resolve.
- evidence 수집: `verify_turn`, `change_turn` (둘 다 0-based event index), `file` (정규화된 절대경로), `verify_quote` (≤120자, 초과 시 trim+`…`), `change_quote` (예: `Edit hooks/foo.sh`).

### Fire 임계

```python
def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= 3
    )
```

→ `verify_keywords` 는 metrics 에만 남고 fire 안 시킨다. 이게 현재 0/8 confirmed 의 직접 원인.

## 5. session-end-retro.sh 변경

```sh
ANALYSIS_JSON=$(python3 "$INFRA_DIR/lib/retro_analyzer.py" "$TRANSCRIPT_PATH" "$SESSION_ID" 2>>"$AI_LOG_FILE")
EXIT_CODE=$?

case "$EXIT_CODE" in
    99) ai_log "no significant patterns, skipping draft"; exit 0 ;;
    0)  ;; # proceed
    *)  ai_log "analyzer failed exit=$EXIT_CODE"; exit 0 ;;
esac

SLUG=$(date +"%Y%m%d-%H%M%S")
DRAFT_FILE="$MEMORY_DIR/feedback-retro-$SLUG-DRAFT.md"
printf '%s' "$ANALYSIS_JSON" | python3 "$INFRA_DIR/lib/retro_analyzer.py" --render > "$DRAFT_FILE"
ai_log "draft created: $DRAFT_FILE"
```

렌더링도 같은 analyzer 가 `--render` 모드로 처리한다 (JSON 은 stdin 으로 수신, 셸 quoting 회피). JSON → 마크다운 변환을 한 곳에 둔다.

## 6. DRAFT 포맷

```markdown
---
name: feedback-retro-YYYYMMDD-HHMMSS
description: "세션 자동 회고 초안 — 사용자 검토 후 확정/폐기"
metadata:
  type: feedback
  status: draft
  session_id: <id>
  signal_count: 2
---

# 자동 회고 초안

session: <id>
metrics: duplicate_reads=[("path", 3)] tool_errors=0 verify_keywords=21

## 🚨 사용자 정정 (1건)
**turn 47** — `assistant: Edit hooks/foo.sh` 직후
> "그게 아니야 — exit 0 이면 회고 알림이 안 떠"

## ⚠️ verify→change (1건)
**turn 51→53** `hooks/session-start-retro-alert.sh`
- verify: "Verified the stdout fix works"
- change: 같은 파일 Edit 재호출

**다음 액션**:
- 확정 시: -DRAFT 제거 + 본문을 feedback memory body 구조(rule + **Why:** + **How to apply:**)로 재작성 + MEMORY.md 인덱스 추가
- 폐기 시: 파일 삭제
```

섹션 출현 규칙:
- 시그널 0건이면 그 섹션 자체를 생략
- 시그널 N건이면 N개 항목 bullet list

## 7. ai_log gap 진단 harness

### `hooks/lib/diag_session_start.sh`

3개 환경에서 `session-start-retro-alert.sh` 와 `lib/log.sh` 의 동작을 순차 호출하고 결과를 표로 정리:

| Env | 설정 | 캡처 항목 |
|---|---|---|
| `normal` | 현재 사용자 셸 그대로 | stdout, stderr, $HOME, AI_LOG_FILE resolved, `.log` write y/n, exit |
| `stripped` | `env -i HOME="$HOME" PATH="$PATH" bash -c ...` | 위 동일 |
| `observed` | SessionStart:startup 실제 env (wrapper 가 사전 캡처한 `/tmp/ss-env-*.txt`) | 위 동일 |

각 환경마다:
1. AI_LOG_FILE 의 resolved 경로 출력 (`echo "$AI_LOG_FILE"`)
2. `mkdir -p "$(dirname "$AI_LOG_FILE")"` 단독 실행 exit code
3. hook 본체 실행 후 AI_LOG_FILE 라인 수 비교 (before / after)

`observed` 환경 캡처용 wrapper 는 임시로 `session-start-retro-alert.sh` 상단에 `env > /tmp/ss-env-$$.txt` 한 줄만 추가 (Phase 6 종료 시 제거).

### 산출물

`docs/reports/diagnostics/YYYY-MM-DD-ai-log-session-start-gap.md`:
- 환경별 결과 표
- 재현 명령 (copy-paste 가능)
- 가설 검증 결과 (어느 가설이 yes/no)
- 추정 root cause + 후속 사이클 작업 제안

### 검증 대상 가설

1. `$HOME` unset → `AI_LOG_FILE` 이 `/.claude/hooks/.log` 로 해석되어 권한 오류
2. `mkdir -p` 가 silent fail 후 append redirect 도 silent
3. launcher 가 `AI_LOG_FILE` 을 다른 경로로 override
4. SessionStart:startup 의 stdout/stderr 가 다른 곳으로 라우팅돼 hook 자체는 실행되지만 ai_log() 의 append 가 실패해도 관측 안 됨

## 8. 테스트

### `hooks/tests/retro_analyzer.test.py`

python `unittest`. 단위테스트 케이스:

- `detect_user_corrections`:
  - 매칭 1건 → 시그널 1
  - 매칭 0건 → 빈 리스트
  - tool_result 내부 텍스트는 매칭 안 됨
  - quote 가 120자 초과 시 trim + `…`
- `detect_verify_then_change`:
  - verify quote 후 ≤5 turn 내 Edit → 시그널
  - verify quote 후 6턴 이후 Edit → 시그널 없음
  - verify quote 만, Edit 없음 → 시그널 없음
  - 다른 파일 Edit → 시그널 없음
- `detect_dup_reads`: path별 ≥3회 정확히 집계
- `count_tool_errors`, `count_verify_keywords`: 단순 카운트 정합성
- `should_fire_draft`: 4가지 케이스
  - 모두 0 → False
  - signals 만 있음 → True
  - dup_reads 만 있음 → True
  - tool_errors=2 (임계 미달) → False
  - tool_errors=3 → True

### Fixtures

각 fixture 는 최소 5~10 events 의 jsonl. 실제 transcript 구조를 따른다 (claude code 의 `tool_name`, `tool_input`, `role`, `content` 형태).

### `hooks/tests/session-end-retro.test.sh` 갱신

기존 end-to-end 흐름 유지 + 새 assertion:
- `transcript-corrections.jsonl` 입력 시 DRAFT 에 `## 🚨 사용자 정정` 섹션 존재
- `transcript-clean.jsonl` 입력 시 DRAFT 파일 미생성 (exit 0, 조용히 종료)

## 9. 마이그레이션 / 롤아웃

1. retro_analyzer.py + 테스트 랜드
2. session-end-retro.sh wrapper 전환
3. DRAFT 포맷 전환 (구버전 DRAFT 파일은 그대로 둠)
4. 다음 3~5개 실제 세션 관찰 → confirmed/discarded 비율 측정. 목표: confirmed ≥ 1/5 (현재 0/8).
5. ai_log gap diagnostic harness 는 위 흐름과 병렬로 별도 사이클. 보고서 commit 시점이 Phase 6 종료.

### 잔존 DRAFT 처리

`feedback-retro-20260611-020753-DRAFT.md`, `feedback-retro-20260611-020817-DRAFT.md` 2건은 spec 채택 시점에 사용자 판단으로 확정 or 폐기. Phase 6 가 직접 건드리지 않는다.

## 10. 성공 기준 (verifiable)

- [ ] `retro_analyzer.test.py` 전부 통과
- [ ] `session-end-retro.test.sh` 전부 통과 (새 assertion 포함)
- [ ] 다음 3~5개 실제 세션에서 confirmed/discarded 비율 측정 결과 confirmed ≥ 1
- [ ] `docs/reports/diagnostics/YYYY-MM-DD-ai-log-session-start-gap.md` 가 4개 가설에 대해 yes/no/unverified 판정 포함
- [ ] 잔존 DRAFT 2건 사용자 처리 완료
