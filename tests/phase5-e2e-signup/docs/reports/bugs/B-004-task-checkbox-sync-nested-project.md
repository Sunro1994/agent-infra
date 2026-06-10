# B-004 — task-checkbox-sync hook 이 nested project layout 에서 동작 안 함

**발견일**: 2026-06-11
**발견 단계**: Task 5.4 Step 5 (signup feature 구현 중)
**스코프**: agent-infra (hook 자체의 버그, 본 sandbox 의 signup feature 와 무관)
**Severity**: High — Phase 5 E2E 의 자동 체크박스 토글 검증이 불가능.

## 증상

`tests/phase5-e2e-signup/index.html` 을 Write/Edit 으로 수정해도 `tests/phase5-e2e-signup/docs/tasks/signup.md` 의 `[T-001]/[T-002]/[T-003]` 가 `[x]` 로 토글되지 않는다. 세 task 모두 `[ ]` 상태로 남는다.

기존 `tests/e2e-sandbox/docs/tasks/signup.md` 도 동일하게 `[ ]` 상태로 남아 있어 Phase 4 시점에도 동일 회귀가 있었던 것으로 추정된다.

## 재현

1. agent-infra 루트에서 `tests/<subdir>/docs/plans/foo.md` 에 `active_task: T-001` 작성.
2. `tests/<subdir>/docs/tasks/foo.md` 에 `- [ ] [T-001] ...` 작성.
3. Edit/Write 로 `tests/<subdir>/some_file` 수정.
4. PostToolUse hook 트리거 → tasks 파일 미토글.

## 근본 원인

`hooks/task-checkbox-sync.sh:19`:
```bash
ROOT=$(cd "$(dirname "$FILE")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
```

`git rev-parse --show-toplevel` 는 git repo 의 최상위만 반환한다. `tests/phase5-e2e-signup/index.html` 의 git toplevel 은 `/Users/leeseonro/agent-infra` (서브디렉토리가 아님).

이어서 `hooks/task-checkbox-sync.sh:23`:
```bash
for plan in "$ROOT/docs/plans/"*.md; do
```

→ `/Users/leeseonro/agent-infra/docs/plans/2026-06-10-agent-infrastructure.md` 만 검사. 이 plan 에는 `active_task` frontmatter 가 없으므로 `ACTIVE_TASK=""` → 조기 종료.

즉 hook 은 "프로젝트 = git repo" 라는 암묵적 가정을 한다. nested sub-project 는 지원하지 않는다.

`hooks/tests/task-checkbox-sync.test.sh` 도 sandbox 에서 `git init` 을 수행하므로 이 케이스를 잡지 못한다.

## 영향

- Phase 4 e2e-sandbox: tasks 파일 `[ ]` 그대로 (이미 발생).
- Phase 5 phase5-e2e-signup: tasks 파일 `[ ]` 그대로 (현재 발견).
- 향후 모든 sub-project 형식의 E2E 또는 monorepo 형식 프로젝트에서 동일 회귀 예상.

## 제안 수정 (구현은 별도 cycle)

`task-checkbox-sync.sh:19` 의 ROOT 결정 로직을 다음으로 교체:

```bash
# file 의 디렉토리부터 위로 올라가며 docs/plans/ 가 존재하는 가장 가까운 디렉토리를 찾는다.
DIR=$(dirname "$FILE")
ROOT=""
while [ "$DIR" != "/" ]; do
    if [ -d "$DIR/docs/plans" ]; then
        ROOT="$DIR"
        break
    fi
    DIR=$(dirname "$DIR")
done
[ -z "$ROOT" ] && ROOT="$PWD"
```

추가로 `hooks/tests/task-checkbox-sync.test.sh` 에 nested case 추가:
- 외부 git repo 내부에 `subproject/docs/plans/` 구조를 만들고, 동일하게 토글되는지 검증.

## 본 E2E 에서의 처리

`docs/tasks/signup.md` 를 수동 토글하지 않고 `[ ]` 상태 그대로 둔다. 이는 Phase 5 산출물 검증 시 "checkbox sync 자동화가 실패했음" 을 명시적으로 드러내기 위함이다. spec §5 의 성공 지표 중 "tasks 3개 모두 `[x]`" 항목은 본 hook 수정이 들어가야 충족된다.

## 다음 단계

- 본 리포트는 발견의 영구 기록으로 보존.
- hook 수정은 Phase 6 또는 별도 hotfix task 로 처리.
- 그동안 nested layout 의 E2E sandbox 는 수동 토글 또는 hook bypass 로 운영.
