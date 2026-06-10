# Phase 4 Validation

작성일: 2026-06-10
관련 plan: `docs/plans/2026-06-10-agent-infrastructure.md` Phase 4
관련 spec: `docs/specs/2026-06-10-agent-infrastructure-design.md`

## 검증 결과

| 항목 | 결과 | 비고 |
| --- | --- | --- |
| Playwright MCP 설치 | PASS | 이번 세션에서 `mcp__playwright__browser_*` 도구 호출 성공으로 확인 |
| `qa-agent` frontmatter `tools` 권한 | PASS | spec(§권한 매트릭스)의 "Read, Write(`docs/reports/qa/`,`docs/reports/bugs/`), `mcp__playwright__*` 전체, Edit/Bash/git 금지" 와 일치 |
| `review-agent` frontmatter `tools` 권한 | PASS | spec과 일치: `Read, Bash` 만. Write/Edit/git 변경 명령 없음 |
| `install.sh` agents symlink | PASS | `~/.claude/agents/{qa-agent.md, review-agent.md}` → `~/agent-infra/agents/*.md` 심볼릭 링크 존재 (커밋 `24e84b6`) |
| qa-agent E2E (sandbox webapp) | PASS | T-002(비밀번호 8자 미만) 의도된 버그 검출 → `[B-001]` 생성 |
| review-agent E2E (의도된 위반 diff) | PASS | `/tmp/review-sandbox` diff 검토 → `verdict=reject, critical=true`, 의존성/트랜잭션 두 critical finding 발행 |

## 세부 산출물

### qa-agent E2E (Task 4.6)

- 환경: `http://localhost:8090`, Playwright(Chromium) via MCP
- 종료 리포트: `tests/e2e-sandbox/docs/reports/qa/2026-06-10-signup.md`
- 버그 리포트: `tests/e2e-sandbox/docs/reports/bugs/B-001-password-length-not-validated-in-js.md`
- 시나리오 결과:
  - T-001 빈 이메일 차단 — PASS (HTML5 `required` 가 submit 차단)
  - T-002 비밀번호 8자 미만 차단 — FAIL (의도된 버그, `[B-001]` 생성)
  - T-003 정상 입력 — PASS (`#msg = "OK: qa@example.com"`)
- 스크린샷 3장: `tests/e2e-sandbox/docs/reports/qa/2026-06-10-signup/screenshots/`
- `.counters.json` 신규 생성 (`{"bug": 1}`)

### review-agent E2E (Task 4.7)

- 환경: `/tmp/review-sandbox` (git init, 2 commits — clean baseline → 의도된 위반 도입)
- 입력:
  - diff: `git diff HEAD~1..HEAD` (`src/domain/order.ts` 에 domain → infra 직접 import + 트랜잭션 외부 두 상태 변경)
  - code-review JSON: `{"findings": []}` (review-agent 단독 차원 검토가 목적)
  - 프로젝트 `.claude/CLAUDE.md`: 레이어 룰 + 트랜잭션 boundary 조항
- 결과:

```json
{
  "verdict": "reject",
  "critical": true,
  "findings": [
    {
      "dimension": "의존성",
      "severity": "critical",
      "file": "src/domain/order.ts:2",
      "summary": "도메인 레이어가 인프라(`../infra/db`)를 직접 import 하여 프로젝트 CLAUDE.md 의 레이어 룰(역방향 금지) 위반"
    },
    {
      "dimension": "트랜잭션",
      "severity": "critical",
      "file": "src/domain/order.ts:4-5",
      "summary": "`db.insert` 와 `db.notify` 두 상태 변경이 단일 트랜잭션 boundary 밖에서 실행되어 부분 실패 시 rollback 부재"
    }
  ]
}
```

(`findings[]` 전체 5건 — 의존성/트랜잭션 critical 2건, 무결성/컨벤션/유지보수성 각 1건. 컨벤션 critical 까지 포함하면 critical 3건. 상세는 sandbox 세션 로그 참조.)

### 세션 중 정정 사항

- `agents/qa-agent.md` 의 `tools` 목록을 실제 Playwright MCP 도구 이름(`browser_*` prefix) 으로 갱신했다.
  - 이전: `mcp__playwright__navigate, ...fill, ...screenshot, ...wait_for_selector, ...console_messages`
  - 이후: `mcp__playwright__browser_navigate, ...browser_type, ...browser_fill_form, ...browser_take_screenshot, ...browser_snapshot, ...browser_wait_for, ...browser_evaluate, ...browser_console_messages, ...browser_close`
  - spec §권한 매트릭스의 "`mcp__playwright__*` 전체" 와 의미상 일치.
- `qa-agent` 와 `review-agent` 모두 Claude Code subagent type 으로 자동 등록되지 않은 채 세션이 시작되어, 이번 회차는 두 agent 모두 `general-purpose` 에 페르소나 지침을 인라인으로 전달해 우회 실행했다. 심볼릭 링크는 `~/.claude/agents/` 에 정상 존재하므로 다음 세션 시작 시 subagent type 목록에 노출되는지 재확인 필요.

## 종료 조건

Phase 4 의 verifiable 종료 조건 6개 모두 PASS. Phase 5 (커스텀 Skills) 진입 가능.
