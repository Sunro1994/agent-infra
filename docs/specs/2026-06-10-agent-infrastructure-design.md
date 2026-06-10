---
title: AI Agent 인프라 통합 설계
date: 2026-06-10
status: draft
owner: leeseonro
---

# AI Agent 인프라 통합 설계

## 1. 목적

`~/.claude/` 글로벌 인프라에 **회고 루프 / 기획 / 코드베이스 / QA / Review / Deploy** 6단계 워크플로우를 일관된 데이터 모델 위에서 자동·반자동으로 수행하는 인프라를 구축한다. 기존 Claude Code 스킬·훅 자산을 최대한 재사용하고, 부족한 부분만 커스텀으로 채운다.

## 2. 스코프

**포함**:
- `~/.claude/` 글로벌 hooks · agents · skills 신설/개편
- 프로젝트 루트 `docs/` 산출물 컨벤션 정의
- 6단계 워크플로우 데이터 흐름
- 단계별 롤아웃 계획

**제외**:
- 회사(Poplus) 학습 워크플로우 통합 — 별도 spec
- Unity 학습 워크플로우 통합 — 별도 spec
- 외부 정적 분석 도구(dependency-cruiser, Semgrep 등) 도입 — Open Questions로 이관

## 3. 결정 로그 (Decision Log)

| # | 결정 사항 | 선택 |
|---|---|---|
| D1 | 스코프 분해 | **단일 통합 spec** |
| D2 | 적용 범위 | **글로벌(~/.claude/) + 프로젝트 오버라이드(.claude/)** |
| D3 | 자동화 수준 | **Hybrid — 감시는 hook, 행위는 skill** |
| D4 | 페르소나 분리 | **선택적 — QA + Review만 sub-agent** |
| D5 | TASK/PRD 위치 | **프로젝트 루트 `docs/tasks/`, `docs/prd/`** (B 옵션) |
| D6 | 회고 산출물 저장 | **메모리 시스템에 feedback 메모리 초안 제안** (사용자 승인 후 반영) |
| D7 | TASK.md 체크박스 동기화 | **명시적 [T-XXX] ID 매핑** |
| D8 | QA 도구 | **Playwright MCP** |
| D9 | Review 구조 | **체이닝: code-review → review-agent** |
| D10 | docs 구조 | **B 옵션 전체 — specs/plans/prd/tasks + reports{qa/bugs/reviews/deploy} + retros** |
| D11 | Phase 4 외부 도구 | **추가 없음 — review-agent만 유지 (원안)** |
| D12 | spec 저장 위치 | **`~/agent-infra/` 별도 프로젝트로 분리** |

## 4. 아키텍처

### 4.1 채널 구조

```
~/.claude/                                  (글로벌 인프라)
├── CLAUDE.md                              ← 원칙 + 페르소나 라우팅 + Deploy 정책
├── settings.json                          ← hooks + sub-agent permissions + 비활성 스킬
├── hooks/                                 (신설 디렉토리)
│   ├── session-end-retro.sh
│   ├── session-start-retro-alert.sh
│   ├── doc-sprawl-warn.sh
│   ├── persona-drift-warn.sh
│   ├── task-checkbox-sync.sh
│   ├── subagent-reload-claude.sh
│   ├── deploy-guard.sh
│   ├── tests/<hook>.test.sh
│   └── .log                               (silent-fail stderr 누적)
├── agents/                                (sub-agent 페르소나)
│   ├── qa-agent.md
│   └── review-agent.md
└── skills/                                (커스텀 스킬)
    ├── integrity-review/SKILL.md
    └── deploy-precheck/SKILL.md

<project-root>/                            (프로젝트 오버라이드)
├── .claude/CLAUDE.md                      ← 도메인 특수규칙만
├── docs/
│   ├── specs/<YYYY-MM-DD>-<topic>.md
│   ├── prd/<feature>.md
│   ├── plans/<feature>.md
│   ├── tasks/<feature>.md
│   ├── reports/
│   │   ├── qa/<YYYY-MM-DD>-<feature>.md
│   │   ├── bugs/<B-NNN>-<slug>.md
│   │   ├── reviews/<feature>-<YYYY-MM-DD>.md
│   │   └── deploy/<YYYY-MM-DD>-<env>.md
│   └── retros/<YYYY-MM>.md                (선택적)
└── .counters.json                         (T-/B- 카운터)
```

### 4.2 컴포넌트 책임 매트릭스

| 컴포넌트 | 채널 | 단일 책임 | 입력 | 출력 |
|---|---|---|---|---|
| `session-end-retro.sh` | SessionEnd hook | transcript 정량 분석 (반복 read, tool error, 검증 단계) | jsonl transcript | `~/.claude/projects/<dir>/memory/feedback-*.md` 초안 |
| `session-start-retro-alert.sh` | SessionStart hook | 직전 회고 초안 알림 | 이전 세션 산출 | 콘솔 메시지 |
| `doc-sprawl-warn.sh` | PostToolUse(Write) hook | 동일 dir md ≥ 5개 시 정리 권유 | tool_input | stderr 경고 |
| `persona-drift-warn.sh` | UserPromptSubmit hook | 영역 키워드 매칭 (기획/코드/QA/리뷰/배포 혼합) | user prompt | stderr 경고 |
| `task-checkbox-sync.sh` | PostToolUse(Edit/Write) hook | 활성 [T-XXX] ID와 diff 매칭 후 토글 | tool_input + active task ID | TASK.md 인플레이스 토글 |
| `subagent-reload-claude.sh` | SubagentStop hook | 메인 컨텍스트에 CLAUDE.md 재주입 안내 | sub-agent stop event | 콘솔 메시지 |
| `deploy-guard.sh` | PreToolUse(Bash) hook | `git commit/push` 차단, deploy-precheck 토큰 검증 | tool_input | `exit 2` (차단) or `exit 0` |
| `qa-agent` | sub-agent | TASK.md 읽기 → playwright 시나리오 → 스크린샷+리포트 | TASK.md + URL | `docs/reports/qa/*`, `docs/reports/bugs/*` |
| `review-agent` | sub-agent | code-review 출력 + diff + CLAUDE.md → 의존성/무결성/확장성 판정 | code-review JSON + diff | `{verdict, findings, critical}` |
| `integrity-review` skill | custom skill | code-review → review-agent 체인 트리거 | feature 식별자 | `docs/reports/reviews/*` |
| `deploy-precheck` skill | custom skill | secret regex + 개인문서 경로 + 하드코딩 패턴 스캔 | staged files | 통과/차단 + 토큰 발급 |

### 4.3 중복 정리 (Phase 1)

- `andrej-karpathy-skills` 플러그인 → `settings.json` `enabledPlugins`에서 `false`
- `code-review` 스킬 유지 (review-agent 입력원)
- `verify` 스킬 유지 (qa-agent 내부 재사용)

## 5. 데이터 흐름

### 5.1 6단계 워크플로우 시퀀스

```
[기획]               [코드베이스]            [QA]              [Review]          [Deploy]
  │                     │                    │                    │                  │
  ▼                     ▼                    ▼                    ▼                  ▼
brainstorming         subagent-driven      qa-agent             code-review       deploy-precheck
  ↓                     ↓                    ↓                    ↓ chain            ↓
docs/specs/*.md       Edit/Write tools     docs/reports/qa/*    review-agent      docs/reports/deploy/*
                        ↓                    docs/reports/bugs/*   ↓
                        ↓                                         verdict
writing-plans         (PostToolUse hook)                          + critical?
  ↓                     ↓
docs/plans/*.md       task-checkbox-sync.sh
  ↓                     ↓
docs/prd/*.md         docs/tasks/<feature>.md
docs/tasks/*.md         [T-XXX] ✓ 자동 토글

                                   ▼ (전 단계 종합)
                              [회고 루프 — 백그라운드]
                                   │
                                   ▼
                              SessionEnd hook
                                   ↓
                              memory/feedback-*.md 초안 제안
```

### 5.2 단계별 세부 흐름

**기획**:
1. 사용자가 자유 대화로 요구사항 제시 → 메인 클로드가 정리하여 `docs/prd/<feature>.md` 초안 작성 (사용자 검토 후 확정)
2. PRD 확정 후 사용자가 `/brainstorming` 호출 → `superpowers:brainstorming` → `docs/specs/<YYYY-MM-DD>-<topic>.md`
3. `superpowers:writing-plans` → `docs/plans/<feature>.md`
4. plan에서 task 추출 → `docs/tasks/<feature>.md`. 각 체크박스에 `[T-NNN]` ID 자동 부여 (counter: `.counters.json`)

**기획 단계 산출물 순서**: PRD → Spec(design) → Plan → Tasks. PRD가 가장 먼저, Tasks는 마지막에 ID 부여까지 끝낸 상태로 생성.

**코드베이스**:
1. 메인이 `superpowers:subagent-driven-development` 호출
2. 활성 task ID를 plan frontmatter `active_task: T-042`에 기록
3. sub-agent Edit/Write → `task-checkbox-sync.sh`가 `[T-042]` 자동 토글
4. sub-agent 종료 → `subagent-reload-claude.sh`가 CLAUDE.md 재주입 메시지

**QA**:
1. 메인이 `qa-agent` 위임. 입력: `docs/tasks/<feature>.md` + 앱 URL
2. qa-agent가 Playwright MCP로 시나리오 실행
3. 스크린샷: `docs/reports/qa/<date>-<feature>/screenshots/`
4. 리포트: `docs/reports/qa/<date>-<feature>.md`
5. 버그 발견 시: `docs/reports/bugs/<B-NNN>-<slug>.md`

**Review (체이닝)**:
1. 사용자가 `/integrity-review` 호출
2. **1단계** — `code-review` 스킬 실행 → JSON
3. **2단계** — `review-agent` 호출. 입력: `[code-review JSON + diff + ~/.claude/CLAUDE.md + 프로젝트 .claude/CLAUDE.md]`
4. structured output: `{verdict: "approve"|"reject", findings: [...], critical: bool}`
5. `docs/reports/reviews/<feature>-<date>.md` 저장

**Critical (Reject) 판정 기준** — 다음 중 하나라도 해당되면 `verdict: "reject"`, `critical: true`:
  - **데이터 손실 가능성**: DB destructive 작업(DROP, TRUNCATE, DELETE WITHOUT WHERE), 파일 비동기 삭제
  - **보안 취약점**: XSS/SQLi/CSRF 미방어, 시크릿 하드코딩, 인증 우회 가능 분기
  - **런타임 crash 가능성**: 명백한 null deref, 무한 루프, 미처리 예외 전파 경로
  - **의존성 방향 위반**: 프로젝트 CLAUDE.md에 명시된 레이어 룰을 어김 (예: 도메인 → 인프라 단일 방향)
  - **트랜잭션 무결성 깨짐**: atomic boundary 외부에서 상태 변경, 부분 실패 시 rollback 부재

**Deploy**:
1. 사용자가 `git commit` 또는 `git push` 시도 → `deploy-guard.sh` 차단
2. 메시지: "deploy-precheck 스킬을 먼저 실행하세요"
3. `/deploy-precheck` 호출 → 검사 항목:
   - secret regex (`API_KEY`, `SECRET`, `PASSWORD`, `TOKEN`, `PRIVATE`)
   - 개인 문서 경로 (`*.local.md`, `plans/`, `notes/`, `scratch/`)
   - 하드코딩된 시크릿 (정규식 매칭)
   - yml/env 환경변수화 여부 (`process.env.X` vs literal)
4. 통과 시 `.claude/.deploy-token-<sha>` 생성, 30분 유효
5. `git commit` 재시도 → 토큰 검증 후 통과

**회고 루프**:
1. `SessionEnd` → `session-end-retro.sh` 실행
2. transcript jsonl 정량 분석:
   - 동일 파일 N회 read (`N ≥ 3`)
   - tool error 횟수 (`error events`)
   - 검증 키워드 빈도 (`verified`, `failed`, `retry`)
3. 패턴 발견 시 `~/.claude/projects/<dir>/memory/feedback-<slug>-DRAFT.md` 생성
4. 다음 세션 `SessionStart` → `session-start-retro-alert.sh`가 DRAFT 목록 표시 → 사용자가 `approve` 또는 `discard`

### 5.3 메모리 시스템과의 관계

- **글로벌 패턴** (모든 프로젝트 공통): `~/.claude/projects/<dir>/memory/feedback-*.md`
- **프로젝트 회고** (이 프로젝트 한정): `<project>/docs/retros/<YYYY-MM>.md`
- 회고 hook은 양쪽 후보 모두 생성 → 사용자가 분류

### 5.4 ID/네이밍 컨벤션

| 종류 | 형식 | 예 | 카운터 |
|---|---|---|---|
| Task | `[T-NNN]` 또는 `[T-NNN.M]` | `[T-042]`, `[T-042.1]` | `.counters.json` `task` |
| Bug | `[B-NNN]` | `[B-007]` | `.counters.json` `bug` |
| Review | 날짜+feature | `auth-2026-06-10.md` | — |
| Spec | 날짜 prefix | `2026-06-10-agent-infra-design.md` | — |
| QA | 날짜+feature | `2026-06-10-login-flow.md` | — |
| Deploy | 날짜+env | `2026-06-10-staging.md` | — |

### 5.5 에러 핸들링

| 시나리오 | 동작 |
|---|---|
| Hook 스크립트 자체 에러 | `exit 0` silent fail, stderr만 `~/.claude/hooks/.log`에 기록. 워크플로우 중단 금지 |
| TASK.md 없는데 ID 매칭 시도 | hook no-op로 통과 (디버그 로그만) |
| Sub-agent 잘못된 결과 | 메인이 검증 (CLAUDE.md `Model Routing` 조항 — 경로 존재 확인, grep 재검증) |
| Playwright MCP 미설치 | qa-agent 즉시 안내 후 종료 (`/install-playwright` 가이드) |
| Deploy 토큰 만료 | "30분 경과, deploy-precheck 재실행 필요" 메시지 |
| review-agent reject | 메인이 사유 요약 후 사용자에게 표시, 다음 단계 진행 차단 |
| Counter file 손상 | 백업(`.counters.json.bak`)에서 복구, 없으면 max(scan TASK.md) + 1로 재구성 |

## 6. 롤아웃 계획

### 6.1 Phase 분리

| Phase | 내용 | 위험도 | 베타 기간 |
|---|---|---|---|
| **1. Foundation** | karpathy-skills 비활성화 · `~/.claude/CLAUDE.md` 개편 · docs/ 컨벤션 문서 작성 · `~/agent-infra/` git init | 낮음 | 즉시 |
| **2. 감시 hooks** | `session-start-retro-alert.sh` · `session-end-retro.sh` · `doc-sprawl-warn.sh` · `persona-drift-warn.sh` | 중 (silent-fail 필수) | 2-3일 |
| **3. 행위 가드 hooks** | `task-checkbox-sync.sh` · `subagent-reload-claude.sh` · `deploy-guard.sh` | 중-고 | 3일 |
| **4. Sub-agents** | `qa-agent.md` (Playwright MCP) · `review-agent.md` (code-review 체이닝) | 중 (권한 설정) | 3일 |
| **5. 커스텀 Skills** | `integrity-review/` · `deploy-precheck/` | 낮음 (사용자 호출) | 2일 |

### 6.2 Phase별 종료 조건 (verifiable)

| Phase | 종료 조건 (모두 충족해야 다음 Phase) |
|---|---|
| 1 | `claude` 재시작 시 CLAUDE.md 정상 로드 · 기존 작업 regression 없음 · `enabledPlugins.andrej-karpathy-skills: false` 확인 |
| 2 | 4개 hook 각자 `<test-fixture>.json` 입력으로 실행 시 `exit 0` · stderr는 `~/.claude/hooks/.log`에만 · UserPromptSubmit 워크플로우 차단 없음 |
| 3 | `[T-001]` 더미 task → Edit → 자동 토글 확인 · `git commit` 차단 메시지 확인 · subagent-reload 메시지 확인 |
| 4 | 더미 webapp에 qa-agent 실행 → 스크린샷+리포트 생성 · 더미 diff에 review-agent → `{verdict, findings, critical}` 출력 |
| 5 | `/integrity-review` 호출 → code-review→review-agent 체인 동작 · `/deploy-precheck` 호출 → 세 카테고리(secret/개인문서/하드코딩) 모두 검출 |

### 6.3 테스팅 전략

**1. Hook 단위 테스트** (`~/.claude/hooks/tests/`):
- 각 hook 옆 `*.test.sh`. 가짜 JSON stdin 주입 → 기대 stdout/stderr/exit code 검증
- `task-checkbox-sync.test.sh`: 사전 준비된 `TASK.md` + `tool_input` 페어 → 토글 결과 diff 비교

**2. Sub-agent 통합 테스트** (`~/tests/agent-infra-sandbox/`):
- Express + React 더미 webapp + 더미 TASK.md
- qa-agent: 로그인/입력검증 시나리오 → 스크린샷 ≥ 2개, 버그리포트 ≥ 1개
- review-agent: 의도적으로 트랜잭션 깬 diff → `verdict: "reject"` 확인

**3. End-to-End 시나리오**:
- 가상 feature "회원가입"을 6단계 모두 통과 → 산출물 9종(spec, prd, plan, tasks, qa, bug, review, deploy report, retro) 모두 생성 확인
- 통과 후 phase 종료 선언

### 6.4 롤백 전략

각 Phase 끝에 `~/.claude/_backups/<phase-N>/` 스냅샷 (settings.json · CLAUDE.md · hooks/ · agents/ · skills/) 저장. 문제 발생 시:

```bash
cp -r ~/.claude/_backups/phase-N/* ~/.claude/
```

## 7. 보안/권한 고려사항

### 7.1 Sub-agent 권한 (`settings.json` `permissions`)

| Sub-agent | 허용 도구 | 차단 도구 |
|---|---|---|
| `qa-agent` | `mcp__playwright__*` 전체, Read, Write (단 path가 `docs/reports/qa/`, `docs/reports/bugs/` 시작 시에만) | Edit, Bash, git 명령 일체 |
| `review-agent` | Read, Bash(`git diff`, `git log`, `git show` 한정 — Bash matcher 정규식으로 enforce), `code-review` 스킬 호출 | Write, Edit, Bash(`commit`, `push`, `rm`, `mv`, `mkdir` 등 변경 명령 일체) |

### 7.2 민감 파일 차단 패턴

deploy-precheck가 차단:
- `.env`, `.env.*` (단 `.env.example` 허용)
- `*.pem`, `*.key`, `*.p12`, `*.pfx`
- `secrets/`, `credentials/`, `.aws/`, `.ssh/`
- 사용자 정의 패턴 (프로젝트별 `.claude/deploy-precheck.ignore`)

## 8. Open Questions / Future Work

1. **외부 정적 분석 통합** — dependency-cruiser/Madge/Semgrep 등을 review-agent 입력으로 추가할지 (현재안: 추가 없음). 필요성 모니터링 후 Phase 6로 별도 진행 가능
2. **회고 분석 정성 단계** — `claude -p`로 transcript 요약을 LLM에 다시 분석시킬지. 토큰 비용 vs 정확도 trade-off
3. **Doc 재정리 임계값** — 현재 `md ≥ 5` 권장값. 사용자 실제 데이터 누적 후 조정
4. **회사(Poplus) 학습 인프라 통합** — 별도 spec
5. **Unity 학습 인프라 통합** — 별도 spec
6. **MCP 서버 자동 설치 스킬** — Playwright MCP 의존성을 자동 설치하는 스킬 (현재안: 수동 가이드)

## 9. 참고

- 사용자 글로벌 가이드: `~/.claude/CLAUDE.md` (Karpathy 5조항)
- 메모리 시스템: `~/.claude/projects/-Users-leeseonro/memory/MEMORY.md`
- 기존 활성 hook: `~/.claude/settings.json` (token-optimizer, 중복 read 차단, Stop 알림)
- 활용하는 기존 스킬:
  - `superpowers:brainstorming` (기획)
  - `superpowers:writing-plans` (기획)
  - `superpowers:writing-skills` (스킬 작성)
  - `superpowers:subagent-driven-development` (코드베이스)
  - `superpowers:dispatching-parallel-agents` (코드베이스)
  - `code-review` (Review 1단계)
  - `verify` (qa-agent 내부)
