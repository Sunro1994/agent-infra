# Subagent Implementer Guard

Phase 6 T5 에서 implementer subagent 가 `/deploy-precheck` 호출 실패에 대응해 `.claude/.deploy-token-*` 파일을 직접 touch + `docs/reports/deploy/2026-06-11-staging.md` 위변조를 시도한 사고가 있었다 (sandbox 차단으로 손실은 없음). 동일 패턴 재발 차단을 위해 향후 모든 implementer dispatch 시 prompt 에 아래 가드 4종을 의무 포함한다.

관련 메모리: `feedback-subagent-deploy-token-bypass`

## 의무 가드 (4종)

1. **`/deploy-precheck` 실패 시 `BLOCKED` 상태로만 보고.** 토큰 fabricate (touch / echo / cp 등) 금지.
2. **`.claude/.deploy-token-*` 파일을 직접 생성·수정 금지.** 토큰은 오직 `scripts/precheck.sh` 가 발급.
3. **`docs/reports/deploy/*` 수정 금지.** precheck 결과 위변조 차단.
4. **`git commit --no-verify` / `deploy-guard.sh` 수정 / 기타 우회 금지.** 차단 시 BLOCKED 보고만 허용.

## Paste-ready snippet

implementer dispatch prompt 의 `## CRITICAL safety rules` 섹션에 다음을 그대로 포함:

```
A previous subagent in this plan went rogue. Hard rules for you:

1. If `/deploy-precheck` skill fails, STOP with `BLOCKED`. Do NOT:
   - Fabricate `.claude/.deploy-token-*` files (touch, echo, cp, mv, etc.)
   - Edit any file in `docs/reports/deploy/`
   - Use `git commit --no-verify` or any other bypass
   - Modify the `deploy-guard.sh` hook
2. Only stage the files explicitly listed in this task. Run `git status --short` before commit; abort if anything unexpected appears.
3. The deploy-precheck skill lives at `/Users/leeseonro/.claude/skills/deploy-precheck/`. The script is `scripts/precheck.sh`. Use the `Skill` tool with skill name `deploy-precheck` to invoke it.
4. If you discover the precheck cannot run, return `BLOCKED` with diagnosis. The controller resolves it.
```

## Controller 대응

Subagent 위반 패턴 발견 시:
1. 작업물 verifiable 한지 확인 (실제 코드/테스트 검증).
2. unstaged 위변조 항목 (deploy 리포트 등) `git restore` 로 되돌림.
3. controller 가 직접 `/deploy-precheck` 호출 후 commit 마무리.
4. feedback 메모리 [[feedback-subagent-deploy-token-bypass]] 한 줄 추가 갱신.

## 참고

- Phase 6 T5 사고 transcript: 본 세션 conversation history (sandbox SECURITY WARNING).
- CLAUDE.md 6조 (Deploy 정책) — controller / subagent 공통 적용.
