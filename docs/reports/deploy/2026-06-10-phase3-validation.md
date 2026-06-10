# Phase 3 Validation

| Hook | Test | 실환경 |
|---|---|---|
| task-checkbox-sync | PASS | (수동) |
| subagent-reload-claude | PASS | (수동) |
| deploy-guard | PASS (4 case) | (수동) |
| settings.json 갱신 | PASS | |
| `git commit` 차단 확인 | (수동) | |
| `[T-XXX]` 토글 확인 | (수동) | |

## 변경사항

- `hooks.PostToolUse[Write]` 에 task-checkbox-sync 추가
- `hooks.PostToolUse[Edit]` 신규 (task-checkbox-sync)
- `hooks.PreToolUse[Bash]` 신규 (deploy-guard)
- `hooks.SubagentStop` 신규 (subagent-reload-claude)

## 백업

- `~/.claude/_backups/agent-infra-phase3-pre.json`

## 새 세션 검증 체크리스트

1. deploy-guard: 더미 git repo에서 `git commit -m test` 시도 → permission deny 응답, `deploy-precheck 토큰` 메시지 표시
2. task-checkbox-sync: `docs/plans/feature.md` 에 `active_task: T-001` 설정, `docs/tasks/feature.md` 에 `[T-001]` 항목 둔 뒤 임의 파일 Edit → `[ ]` → `[x]` 자동 토글
3. subagent-reload-claude: sub-agent 호출 후 종료 시 `🔁 sub-agent '...' 종료. CLAUDE.md 재확인` stderr 출력

## 위험도 메모

deploy-guard 적용 후 Phase 5 deploy-precheck 스킬 구현 전까지는 commit/push가 모두 차단된다. 단, `<repo>/.claude/.deploy-token-<sha>` 파일을 30분 mtime으로 직접 touch하면 우회 가능 (개발/검증 목적). Phase 5에서 정식 토큰 발급 경로가 들어온다.
