# Signup — PRD

**Spec**: [`docs/specs/2026-06-10-signup.md`](../specs/2026-06-10-signup.md)
**상태**: Draft → Active (Plan 작성 직전)

## 1. 배경

agent-infra Phase 5 (Skill 통합) 완료 후, 전체 파이프라인이 실제로 9종 산출물을 생성하는지 확인할 수단이 필요하다. 실제 프로덕션 feature 로는 변수가 너무 많으므로, 통제된 가상 feature 1개를 끝까지 돌려 검증한다.

이 PRD 는 검증 타겟인 "signup" feature 의 요구사항을 정의한다. **요구사항 자체는 단순하지만, "의도된 버그가 포함된 채로 제출"되는 점이 핵심**이다 — 파이프라인의 후속 단계(QA, integrity-review)가 이 버그를 실제로 잡아내는지가 검증 포인트다.

## 2. 목표

- 사용자가 이메일·비밀번호로 회원가입 시도를 흉내낼 수 있는 단일 페이지 폼을 제공한다.
- 3개 의도된 결함을 코드에 포함해 QA·integrity-review 가 실제로 발견하는지 측정한다.
- 9종 산출물(spec, PRD, plan, tasks, 구현물, QA 리포트+버그, review, precheck, commit)이 모두 파일 시스템에 생성된 상태로 종료한다.

## 3. 비목표

- 실제 회원가입 동작(백엔드 저장, 인증, 이메일 발송 등) 구현.
- 비밀번호 해싱, 세션, 토큰 발급.
- 반응형 레이아웃, 다국어, 접근성 audit.
- 의도된 버그 수정. (E2E 종료 후 별도 cycle 에서 다룬다.)

## 4. 사용자 스토리

- **U1 — 정상 가입 시도**
  사용자로서 유효한 이메일과 8자 이상 비밀번호를 입력하면 "OK: <email>" 초록색 메시지를 본다.

- **U2 — 이메일 형식 오류 차단**
  사용자로서 `@` 가 빠진 이메일을 제출하면 "이메일 형식이 올바르지 않습니다" 빨간색 메시지를 본다.

- **U3 — 짧은 비밀번호 차단**
  사용자로서 8자 미만 비밀번호를 입력하면 브라우저 기본 검증으로 제출이 막힌다.

## 5. 기능 요구사항

| ID | 요구사항 | Task |
|---|---|---|
| FR-1 | 이메일 입력 필드와 JS 정규식 검증을 제공한다. | T-001 |
| FR-2 | 비밀번호 입력 필드와 길이 ≥ 8 검증을 제공한다. | T-002 |
| FR-3 | 모든 검증 통과 시 "OK: <email>" 메시지를 표시한다. | T-003 |
| FR-4 | 검증 실패 메시지는 빨간색, 성공 메시지는 초록색으로 표시한다. | T-001 ~ T-003 분산 |

## 6. 의도된 결함 (Known Defects)

E2E 검증을 위해 의도적으로 포함된다. QA·review 가 발견해야 한다.

| ID | 결함 | 어디서 잡혀야 하는가 |
|---|---|---|
| KD-1 | 이메일 정규식이 `/@/` 로 느슨 → `a@b` 통과 | QA Step 6 → B-001 |
| KD-2 | 비밀번호 길이 검증을 HTML5 `minlength` 에만 의존 → DevTools 우회 가능 | QA Step 6 → B-002 |
| KD-3 | 성공 메시지를 `innerHTML` 로 렌더 → XSS | QA Step 6 → B-003, integrity-review Step 7 (코드 레벨) |

## 7. 비기능 요구사항

- **단일 파일**: `index.html` 하나로 완결. 외부 자산 없음.
- **빌드 없음**: `python3 -m http.server 8000` 또는 file:// 로 즉시 실행.
- **브라우저**: Chromium 최신 (Playwright MCP 기본).

## 8. 성공 지표

본 feature 의 "성공"은 사용자 경험이 아니라 파이프라인 산출물 완성도로 측정한다.

- [ ] `tests/phase5-e2e-signup/index.html` 존재, 3개 의도된 결함 포함
- [ ] `docs/tasks/signup.md` 3개 항목 모두 `[x]`
- [ ] `docs/reports/qa/2026-06-11-signup.md` + 스크린샷 ≥ 6장
- [ ] `docs/reports/bugs/B-001-*.md`, `B-002-*.md`, `B-003-*.md` 각 1개
- [ ] `docs/reports/reviews/signup-2026-06-11.md` 1개 (verdict 무관)
- [ ] `.claude/.deploy-token-*` 1개 (precheck PASS) 또는 차단 리포트 1개
- [ ] `git log` 에 commit 1개 (deploy-guard 통과)

## 9. 의존성

- agent-infra Phase 1~5 설치 완료 (`hooks/`, `agents/`, `skills/`).
- `~/.claude/skills/` 에 `integrity-review`, `deploy-precheck` symlink 존재.
- Playwright MCP 사용 가능 (qa-agent 호출용).

## 10. Open Questions

없음. spec §6 의 운영 결정으로 모두 해소됨.
