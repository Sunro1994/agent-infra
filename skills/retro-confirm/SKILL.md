---
name: retro-confirm
description: 회고 hook이 생성한 feedback-retro-*-DRAFT.md 일괄 검토 + 분류. 사용 시점 — DRAFT가 5개 이상 누적됐을 때, 또는 SessionStart 알림에 DRAFT 목록이 표시될 때. 사용자가 `/retro-confirm` 또는 "회고 검토", "DRAFT 정리" 라고 부를 때. confirm/discard/merge 4지선다로 분류 후 메모리 승격까지 일괄 처리.
---

# Retro Confirm Skill

## 목적

`session-end-retro.sh` hook이 생성한 `feedback-retro-*-DRAFT.md` 파일들이 메모리에 승격되지 않고 누적되는 문제를 해결한다. 사용자가 한 번의 호출로 모든 DRAFT를 분류·정리한다.

## Workflow

### Stage 1 — DRAFT 수집

1. `MEMORY_DIR=$HOME/.claude/projects/-Users-leeseonro/memory` 에서 `feedback-retro-*-DRAFT.md` 전체 목록 추출
2. 없으면 "검토할 DRAFT 없음" 출력 후 종료
3. 각 DRAFT에 대해 다음을 파싱:
   - `session_id`, `signal_count`, `metrics`
   - 신호 본문 (user_correction quote 첫 3개)

### Stage 2 — 자동 분류 제안

각 DRAFT를 다음 기준으로 분류 후 사용자에게 제안:

| 기준 | 분류 |
|---|---|
| signal_count=0 (metric 단독 fire) | `discard` 추천 |
| user_correction 모든 quote가 코드/JSON 패턴 (백틱·중괄호·세미콜론·따옴표 다수) | `discard` 추천 |
| signal이 모두 단일 단어 "다시"·"stop"·"잠깐" 매치이고 작업 요청 형태 | `discard` 추천 |
| 동일 도메인 패턴이 기존 feedback 메모리에 이미 있음 | `merge` 추천 |
| signal_count ≥ 2 + 일반화 가능한 패턴 | `confirm` 추천 |
| 그 외 보더라인 | `skip` 추천 |

### Stage 3 — 사용자 일괄 결정

AskUserQuestion 으로 각 DRAFT의 분류를 한 번에 확인받는다. 한 질문당 DRAFT 1개씩, 최대 4개 옵션:
- `confirm` — 메모리로 승격
- `discard` — 삭제
- `merge` — 기존 메모리에 합치기
- `skip` — 보류

DRAFT가 5개 이상이면 자동 분류 결과를 표로 먼저 보여주고 "이 분류대로 진행할까요?" 단일 질문으로 일괄 승인 받는다.

### Stage 4 — 실행

**confirm 처리**:
1. 메모리 슬러그를 사용자에게 받음 (예: `feedback-mermaid-validation`)
2. rule + **Why:** + **How to apply:** 3섹션 골격을 사용자가 채우도록 요청 (또는 메인이 DRAFT 신호에서 일반화 초안 작성 → 사용자 검수)
3. `$MEMORY_DIR/<slug>.md` 작성. frontmatter에 `source_drafts:` 리스트 포함
4. `$MEMORY_DIR/MEMORY.md`에 인덱스 1줄 추가
5. 원본 DRAFT 삭제

**discard 처리**:
- DRAFT 파일 삭제

**merge 처리**:
1. 대상 메모리 파일 선택 (사용자 또는 메인 추천)
2. 기존 메모리에 신호 요약을 추가 (rule 강화 또는 예시 추가)
3. `metadata.source_drafts` 에 추가
4. 원본 DRAFT 삭제

**skip 처리**:
- 그대로 둠 (다음 호출에서 다시 검토 대상)

### Stage 5 — 결과 보고

요약 표 출력:
- confirmed: N개 (메모리 슬러그 목록)
- merged: M개 (대상 메모리 목록)
- discarded: K개
- skipped: J개
- 최종 DRAFT 잔여 수

## Inputs

- `mode` (`interactive`|`auto-discard-fp`, 기본 `interactive`):
  - `interactive`: 모든 DRAFT 개별 결정
  - `auto-discard-fp`: 자동 `discard` 추천 항목은 묻지 않고 삭제

## 실패 모드

- MEMORY_DIR 없음 → 에러 후 종료
- MEMORY.md 없음 → 신규 생성 (빈 인덱스로 시작)
- 슬러그 충돌 (이미 존재) → 사용자에게 덮어쓰기·이름변경·skip 선택 요청

## 메모리 본문 골격

confirm 처리 시 다음 골격을 사용. 본문 작성 가이드는 `~/.claude/CLAUDE.md` auto memory 섹션 `feedback` 타입 `<body_structure>` 참고.

```markdown
---
name: <slug>
description: <한 줄 요약 — 미래 세션 관련성 판단용>
metadata:
  type: feedback
  source_drafts:
    - feedback-retro-<YYYYMMDD-HHMMSS>
---

<규칙 — 무엇을 할지/하지 말지>

**Why**: <이유 — 사용자가 제시한 사례·강한 선호·과거 incident>

**How to apply**: <언제·어디서 이 규칙이 발동되는지>

관련: [[<related-slug>]]
```

## 호출 예

```
/retro-confirm
/retro-confirm --mode auto-discard-fp
```
