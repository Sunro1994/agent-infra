---
name: integrity-review
description: code-review → review-agent 체이닝 리뷰. 의존성 방향, 트랜잭션 정합성, 무결성, 유지보수성, 확장성, CLAUDE.md 컨벤션, 치명 버그를 종합 검토. 사용 시점 — 기능 구현 완료 후, PR 생성 직전. 사용자가 `/integrity-review` 또는 "통합 리뷰", "정합성 리뷰" 라고 부를 때.
---

# Integrity Review Skill

## Workflow

1. **Stage 1 — code-review**: `code-review` 스킬을 medium effort로 실행. 결과 JSON 보관.
2. **Stage 2 — review-agent 위임**: `review-agent` sub-agent 를 호출. 입력:
   - Stage 1 JSON
   - `git diff <base>...HEAD` (base는 사용자가 지정, 기본값 `main`)
   - `~/.claude/CLAUDE.md`
   - 프로젝트 `.claude/CLAUDE.md` (있다면)
   - `docs/specs/` 최근 1개

3. **Stage 3 — 리포트 작성**:
   - 출력 경로: `docs/reports/reviews/<feature>-<YYYY-MM-DD>.md`
   - 내용: Stage 1 요약 + Stage 2 verdict + findings 목록
4. **Stage 4 — 결정**:
   - `verdict: reject` → 사용자에게 critical findings 표시하고 다음 단계(deploy 등) 진행 차단
   - `verdict: approve` → 통과 표시

## Inputs

- `feature` (string): 리뷰 대상 식별자 (파일명에 사용)
- `base` (string, 기본 `main`): diff 비교 기준
- `effort` (low|medium|high, 기본 medium): code-review 스킬 effort

## 사용 예

```
/integrity-review --feature signup --base main --effort high
```

## 실패 모드

- `code-review` 스킬 없음 → 에러 메시지 표시 후 종료
- `review-agent` 등록 안됨 → 에러 메시지 표시 후 종료
- diff 비어있음 → "검토 대상 변경 없음" 출력 후 종료
