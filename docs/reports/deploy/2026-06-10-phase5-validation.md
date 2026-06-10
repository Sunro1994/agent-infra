# Phase 5 Validation

작성일: 2026-06-10
관련 plan: `docs/plans/2026-06-10-agent-infrastructure.md` Phase 5
관련 spec: `docs/specs/2026-06-10-agent-infrastructure-design.md`

## 검증 결과

| 항목 | 결과 | 비고 |
| --- | --- | --- |
| `integrity-review` SKILL.md 구조 검토 | PASS | code-review → review-agent 체이닝, 입력/출력/실패모드 spec 일치 |
| `deploy-precheck` SKILL.md 구조 검토 | PASS | 검사 카테고리 3종 + 토큰 발급 + 이그노어 패턴 spec 일치 |
| `deploy-precheck` `precheck.sh` 단위 테스트 | PASS (3 case) | clean staged → 토큰 발급 / `.env` staged → 차단 / 하드코딩 → 차단 |
| `install.sh` skills/*/ 개별 symlink | PASS | `~/.claude/skills/{integrity-review, deploy-precheck}` 심볼릭 링크 생성 확인 |
| 통합 E2E (signup 6단계, 9종 산출물) | **PENDING** | Task 5.4 — 새 세션 수동 수행 |
| 회고 DRAFT → 다음 세션 알림 | **PENDING** | Task 5.4 부속 검증 |

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

## 사이클 완성도

`deploy-precheck` 가 빌드되어 CLAUDE.md 6조의 사이클이 형식적으로 닫혔다:

1. 사용자 commit/push 의도
2. `/deploy-precheck` 호출 → `<root>/.claude/.deploy-token-<sha>` 발급
3. `git commit` → `deploy-guard.sh` 가 토큰 mtime < 30분 검증 → 통과
4. 토큰 30분 후 자동 만료

다음 세션에서 새 스킬이 `/` 슬래시 메뉴에 등장하는지, Task 5.4 통합 E2E 9종 산출물이 모두 생성되는지가 마지막 verifiable 조건이다.

## 종료 조건

Phase 5 의 verifiable 종료 조건 6개 중 4개 PASS, 2개 PENDING (수동 E2E 영역).
4개 PASS 기준으로 Task 5.1~5.3 의 빌드는 완료. Task 5.4 / 5.5 추가 검증 후 v0.1.0 태깅 권장.
