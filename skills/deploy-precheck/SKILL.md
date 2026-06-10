---
name: deploy-precheck
description: 배포 전 secret leak, 개인 문서, 하드코딩된 시크릿을 검사하고 토큰 발급. 사용 시점 — git commit/push 직전. 사용자가 `/deploy-precheck` 또는 "배포 점검", "deploy 검사" 라고 부를 때. 통과 시 30분 유효 토큰 발급, deploy-guard hook이 이 토큰을 검증해야 commit/push 통과.
---

# Deploy Precheck

## Workflow

1. `git status --short` 로 staged 파일 목록 추출 (없으면 unstaged + untracked 포함하여 검사 대상 산정)
2. `scripts/precheck.sh` 실행 — 3개 카테고리 검사:
   - **Secret regex**: API_KEY, SECRET, PASSWORD, TOKEN, PRIVATE_KEY 패턴
   - **개인 문서 경로**: `*.local.md`, `plans/`, `notes/`, `scratch/`, `.claude/.deploy-token-*`
   - **하드코딩**: `process.env.X` 가 아닌 string literal로 secret 패턴 매칭
3. 발견 시: 결과 표 출력 + 토큰 미발급 + 사용자에게 수정 안내
4. 통과 시: `<project-root>/.claude/.deploy-token-<sha256>` 생성 (mtime이 토큰 발행 시점)
5. 리포트: `docs/reports/deploy/<YYYY-MM-DD>-<env>.md` (env 기본값: `staging`)

## Inputs

- `env` (string, 기본 `staging`): 리포트 파일명에 사용
- `mode` (`staged`|`all`, 기본 `staged`): 검사 대상 범위

## 실패 모드

- git repo 아님 → 에러 후 종료
- `.deploy-token-*` 가 검사 대상에 포함되면 즉시 차단 (토큰 자체 leak 방지)

## 사용자 정의 패턴

`<project-root>/.claude/deploy-precheck.ignore` 가 있으면 해당 파일에 명시된 path를 검사에서 제외.
