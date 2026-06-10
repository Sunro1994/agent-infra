# ID / 네이밍 컨벤션

| 종류 | 형식 | 예시 | 카운터 소스 |
|---|---|---|---|
| Task | `[T-NNN]` 또는 `[T-NNN.M]` (서브태스크) | `[T-042]`, `[T-042.1]` | `<project>/.counters.json` 의 `task` 키 |
| Bug | `[B-NNN]` | `[B-007]` | `<project>/.counters.json` 의 `bug` 키 |
| Review | `<feature>-<YYYY-MM-DD>.md` | `auth-2026-06-10.md` | — |
| Spec | `<YYYY-MM-DD>-<topic>.md` | `2026-06-10-agent-infra-design.md` | — |
| QA | `<YYYY-MM-DD>-<feature>.md` | `2026-06-10-login-flow.md` | — |
| Deploy | `<YYYY-MM-DD>-<env>.md` | `2026-06-10-staging.md` | — |

## .counters.json 포맷

```json
{
  "task": 42,
  "bug": 7,
  "last_updated": "2026-06-10T12:34:56Z"
}
```

손상 시 백업(`.counters.json.bak`)에서 복구, 없으면 `grep -oE '\[T-\d+\]' docs/tasks/*.md | sort -u | tail -1` 로 max 값을 찾아 +1.

## 활성 Task 표시 (코드베이스 단계)

작업 중인 task ID는 plan 파일 frontmatter에 명시한다:

```yaml
---
title: 회원가입 구현
active_task: T-042
---
```

`task-checkbox-sync.sh` hook은 이 값을 읽어 Edit/Write 시 자동 토글한다.
