# Phase 5 Validation

작성일: 2026-06-10 (초안), 2026-06-11 갱신 (E2E 결과 반영), 2026-06-11 재갱신 (retro alert surface 진단 + fix)
관련 plan: `docs/plans/2026-06-10-agent-infrastructure.md` Phase 5
관련 spec: `docs/specs/2026-06-10-agent-infrastructure-design.md`
E2E commit: `5e4e5e0`

## 검증 결과

| 항목 | 결과 | 비고 |
| --- | --- | --- |
| `integrity-review` SKILL.md 구조 검토 | PASS | code-review → review-agent 체이닝, 입력/출력/실패모드 spec 일치 |
| `deploy-precheck` SKILL.md 구조 검토 | PASS | 검사 카테고리 3종 + 토큰 발급 + 이그노어 패턴 spec 일치 |
| `deploy-precheck` `precheck.sh` 단위 테스트 | PASS (3 case) | clean staged → 토큰 발급 / `.env` staged → 차단 / 하드코딩 → 차단 |
| `install.sh` skills/*/ 개별 symlink | PASS | `~/.claude/skills/{integrity-review, deploy-precheck}` 심볼릭 링크 생성 확인 |
| 통합 E2E (signup 6단계, 9종 산출물) | **PASS** | Task 5.4 — `tests/phase5-e2e-signup/` 에서 신규 9종 산출물 모두 생성, commit `5e4e5e0` |
| 회고 DRAFT → 다음 세션 알림 | **PENDING** (재진단 완료, 다음 세션 final verify) | 원인 규명: stderr 출력이 transcript attachment 에만 보존되고 system-reminder 로 surface 안 됨 → `hooks/session-start-retro-alert.sh` 의 `printf >&2` 를 stdout 으로 전환. 새 세션에서 alert 가 system-reminder 로 surface 되면 PASS |

## 세부

### Task 5.1 — integrity-review

- 파일: `skills/integrity-review/SKILL.md`
- Workflow: Stage 1 `/code-review` → Stage 2 `review-agent` → Stage 3 `docs/reports/reviews/<feature>-<YYYY-MM-DD>.md` → Stage 4 verdict 기반 분기
- Inputs: `feature`, `base` (기본 `main`), `effort` (기본 `medium`)
- 실패 모드 명시: code-review 부재, review-agent 미등록, diff 비어있음 3가지

### Task 5.2 — deploy-precheck

- 파일: `skills/deploy-precheck/SKILL.md`, `skills/deploy-precheck/scripts/precheck.sh`
- 단위 테스트 결과 (`/tmp/precheck-sandbox`):
  - Case 1 clean staged → exit 0, 토큰 `.claude/.deploy-token-238591e18c6a` 발급
  - Case 2 `.env` staged → exit 1, "Secret 파일 경로" 차단 메시지
  - Case 3 하드코딩 `API_KEY = "sk-..."` → exit 1, "하드코딩된 시크릿 패턴" 차단 메시지
- 토큰 자체 leak 방지(`.claude/.deploy-token-*` 가 staging 후보면 즉시 차단) 로직 포함
- 이그노어 파일: `<root>/.claude/deploy-precheck.ignore` (선택)

### Task 5.3 — install.sh 갱신

- 변경: `[1/4]` → `[1/5]` 로깅, 4번째 단계로 `skills/*/` 개별 symlink 루프 추가
- 재실행 결과:
  - `~/.claude/skills/integrity-review` → `~/agent-infra/skills/integrity-review`
  - `~/.claude/skills/deploy-precheck` → `~/agent-infra/skills/deploy-precheck`
- 새 백업: `~/.claude/_backups/agent-infra-20260610-221342/`

### Task 5.4 — 통합 E2E (signup 9종 산출물)

작업 디렉토리: `tests/phase5-e2e-signup/`
실행일: 2026-06-11
종료 commit: `5e4e5e0 test(phase5-e2e): signup feature 9-artifact E2E run`

| # | 산출물 | 경로 | 비고 |
|---|---|---|---|
| 1 | spec | `docs/specs/2026-06-10-signup.md` | `/brainstorming` |
| 2 | PRD | `docs/prd/signup.md` | 사용자 요청 후 작성 |
| 3 | plan (frontmatter `active_task: T-001`) | `docs/plans/signup.md` | `/writing-plans` |
| 4 | tasks 체크박스 | `docs/tasks/signup.md` | **3개 모두 `[ ]`** (B-004 영향) |
| 5 | 구현 (3 의도된 결함) | `index.html` 44 lines | subagent-driven-development × 3 |
| 6 | QA 리포트 + 6장 스크린샷 + B-001/B-002/B-003 | `docs/reports/qa/`, `docs/reports/bugs/` | qa-agent + Playwright MCP, 정상 path 3 + KD 재현 3 |
| 7 | integrity-review 리포트 | `docs/reports/reviews/signup-2026-06-11.md` | verdict=**reject**, critical=true (XSS) — spec §6 운영 결정에 따라 진행 |
| 8 | deploy-precheck PASS + 토큰 | `.claude/.deploy-token-dc5ebd52d0e9` (mtime 01:22) + `docs/reports/deploy/2026-06-11-staging.md` | secret 0건 |
| 9 | git commit + deploy-guard 통과 | commit `5e4e5e0`, hook log `[deploy-guard] token valid` | 사용자 명시 승인 후 실행 |

**별건 발견사항**: **B-004 — `task-checkbox-sync.sh` 가 nested project layout 미지원**
- 위치: `tests/phase5-e2e-signup/docs/reports/bugs/B-004-task-checkbox-sync-nested-project.md`
- 원인: `hooks/task-checkbox-sync.sh:19` 가 `git rev-parse --show-toplevel` 로 ROOT 를 결정 → sub-project 의 `docs/plans/` 가 아닌 repo root 의 `docs/plans/` 을 검사
- 영향: tasks 체크박스 자동 토글이 nested layout (e2e-sandbox, phase5-e2e-signup) 에서 모두 실패
- **처리 (완료)**: hotfix commit `c991d15` — `task-checkbox-sync.sh` 의 ROOT 결정 로직을 walk-up 방식으로 교체 + `hooks/tests/task-checkbox-sync.test.sh` 에 nested case 추가

### Task 5.4 부속 — retro alert surface 미발화 진단 (2026-06-11 추가)

실행일: 2026-06-11 새 세션 시작 시 `📋 [agent-infra] 직전 세션 회고 초안 ...` system-reminder 가 surface 되지 않음을 확인.

| 확인 사항 | 결과 |
| --- | --- |
| Hook 등록 (`~/.claude/settings.json` SessionStart) | 정상 |
| Hook 실행 (transcript attachment `hookName: SessionStart:startup`, `exitCode: 0`) | 정상 실행됨 |
| Stderr 보존 | attachment `stderr` 필드에 alert 본문 정상 보존 |
| Stdout surface | **stderr 만 채워져 있어 system-reminder 가 안 뜸** |

비교: Token Optimizer 와 Superpowers SessionStart hook 둘 다 stdout (plain text or JSON `hookSpecificOutput.additionalContext`) 사용 → system-reminder 로 정상 surface.

**Fix**: `hooks/session-start-retro-alert.sh` 의 `printf "..." >&2` 3 라인을 stdout 으로 전환. Manual 실행으로 stdout 출력 확인 (`exit 0`). 새 세션 시작 시 system-reminder 가 실제로 surface 되면 본 PENDING 항목을 PASS 로 종료한다.

**별건 (보류)**: 진단 도중, 이번 세션에선 transcript attachment 엔 hook 실행이 기록되었지만 `~/.claude/hooks/.log` 엔 해당 세션의 entry 가 누락되었다. `SessionStart:startup` 환경에서 `$HOME` 또는 ai_log 파일 path 가 달라졌을 가능성. surface 문제와 별개 사이클로 분리.

## 사이클 완성도

`deploy-precheck` 가 빌드되어 CLAUDE.md 6조의 사이클이 형식적으로 닫혔다:

1. 사용자 commit/push 의도
2. `/deploy-precheck` 호출 → `<root>/.claude/.deploy-token-<sha>` 발급
3. `git commit` → `deploy-guard.sh` 가 토큰 mtime < 30분 검증 → 통과
4. 토큰 30분 후 자동 만료

다음 세션에서 새 스킬이 `/` 슬래시 메뉴에 등장하는지, Task 5.4 통합 E2E 9종 산출물이 모두 생성되는지가 마지막 verifiable 조건이다.

## 종료 조건

Phase 5 verifiable 종료 조건 6개 중 **5개 PASS, 1개 PENDING (재진단 완료)**.

- PASS: integrity-review 구조 / deploy-precheck 구조 / precheck.sh 단위테스트 / install.sh symlink / **통합 E2E 9종 산출물**
- PENDING: 회고 DRAFT 알림 surface — 원인 규명 완료, stderr→stdout fix 적용. 새 세션 시작 시 system-reminder 가 뜨면 PASS.

별건 발견:
- B-004 (task-checkbox-sync nested-project) — hotfix commit `c991d15` 완료
- ai_log 미기록 (SessionStart:startup 환경) — 별도 사이클로 분리

surface fix 검증 후 v0.1.0 태깅.
