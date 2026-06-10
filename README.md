# agent-infra

`~/.claude/` 글로벌 인프라 — 6단계 dev 워크플로우(회고/기획/코드/QA/Review/Deploy)를 자동·반자동으로 수행.

## 구조

- `hooks/` — Claude Code hooks
- `agents/` — sub-agent 페르소나 정의 (qa-agent, review-agent)
- `skills/` — 커스텀 스킬 (integrity-review, deploy-precheck)
- `docs/specs/` — 설계 spec
- `docs/plans/` — 구현 plan
- `docs/conventions/` — 산출물 컨벤션

## 설치

```bash
./install.sh
```

`~/.claude/{hooks,agents,skills}/` 로 symlink 생성. CLAUDE.md와 settings.json은 install.sh가 직접 수정 (sentinel 라인 기반).

## 제거

```bash
./uninstall.sh
```

## Phase

이 인프라는 Phase 1~5로 점진 배포. 각 Phase는 `_backups/phase-N/` 스냅샷 자동 생성. 자세한 사항은 `docs/plans/2026-06-10-agent-infrastructure.md` 참조.
