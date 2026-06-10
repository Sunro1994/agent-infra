# Agent Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `~/.claude/` 글로벌 인프라에 6단계 워크플로우(회고/기획/코드/QA/Review/Deploy)를 자동·반자동 수행하는 hooks · agents · skills 시스템을 5 Phase로 점진 배포한다.

**Architecture:** `~/agent-infra/` 별도 git repo에서 모든 자산을 관리하고, `install.sh`로 `~/.claude/{hooks,agents,skills}/`에 symlink를 만들어 배포한다. CLAUDE.md와 settings.json은 직접 수정(symlink 부적합). 각 Phase는 자체 종료 조건을 만족해야 다음 Phase로 진행.

**Tech Stack:** bash (POSIX), `jq` (JSON 파싱), Python 3 (transcript jsonl 분석), Claude Code hooks (UserPromptSubmit / PreToolUse / PostToolUse / SessionStart / SessionEnd / SubagentStop), Playwright MCP, Claude Code sub-agents.

**Spec reference:** `docs/specs/2026-06-10-agent-infrastructure-design.md`

---

## Phase 0: 준비 (이미 완료)

- [x] `~/agent-infra/` git init + main 브랜치
- [x] `docs/specs/2026-06-10-agent-infrastructure-design.md` 작성·커밋

---

## Phase 1: Foundation (위험도 낮음)

목표: 환경 정리, CLAUDE.md 개편, 컨벤션 문서화, install.sh 뼈대 작성.
종료 조건: `claude` 재시작 시 CLAUDE.md 정상 로드, regression 없음, karpathy 플러그인 비활성화 확인.

### Task 1.1: README.md 작성

**Files:**
- Create: `~/agent-infra/README.md`

- [ ] **Step 1: README.md 작성**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add README"
```

### Task 1.2: docs/conventions/docs-structure.md 작성

**Files:**
- Create: `~/agent-infra/docs/conventions/docs-structure.md`

- [ ] **Step 1: 컨벤션 문서 작성**

```markdown
# docs/ 디렉토리 컨벤션

각 프로젝트 루트 `docs/` 아래는 산출물 타입별로 그루핑한다.

```
docs/
├── specs/<YYYY-MM-DD>-<topic>.md       — 설계/디자인 (brainstorming 산출)
├── prd/<feature>.md                     — 제품 요구사항
├── plans/<feature>.md                   — 구현 전략 (writing-plans 산출)
├── tasks/<feature>.md                   — [T-NNN] 체크박스 작업 목록
└── reports/
    ├── qa/<YYYY-MM-DD>-<feature>.md     — QA agent 실행 리포트
    ├── bugs/<B-NNN>-<slug>.md           — QA 중 발견한 개별 버그
    ├── reviews/<feature>-<YYYY-MM-DD>.md — code-review + review-agent 결합
    └── deploy/<YYYY-MM-DD>-<env>.md     — deploy-precheck 결과
```

`docs/retros/<YYYY-MM>.md` 는 선택. 프로젝트 단위 회고가 필요한 경우만 생성.

## 산출물 생성 순서 (기획 단계)

PRD → Spec(design) → Plan → Tasks

각 단계는 직전 산출물을 참조한다. Plan에서 추출한 task는 마지막에 ID(`[T-NNN]`)를 부여해 Tasks 파일에 적재.
```

- [ ] **Step 2: Commit**

```bash
git add docs/conventions/docs-structure.md
git commit -m "docs: add docs/ structure convention"
```

### Task 1.3: docs/conventions/id-naming.md 작성

**Files:**
- Create: `~/agent-infra/docs/conventions/id-naming.md`

- [ ] **Step 1: ID 컨벤션 문서 작성**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
git add docs/conventions/id-naming.md
git commit -m "docs: add ID/naming convention"
```

### Task 1.4: install.sh 뼈대 작성

**Files:**
- Create: `~/agent-infra/install.sh`
- Create: `~/agent-infra/uninstall.sh`

- [ ] **Step 1: install.sh 작성 (Phase 1 분량만)**

```bash
#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_DIR="$CLAUDE_DIR/_backups/agent-infra-$(date +%Y%m%d-%H%M%S)"

echo "==> agent-infra installer"
echo "    source: $INFRA_DIR"
echo "    target: $CLAUDE_DIR"
echo "    backup: $BACKUP_DIR"

# 1. 백업
mkdir -p "$BACKUP_DIR"
cp -r "$CLAUDE_DIR/settings.json" "$BACKUP_DIR/" 2>/dev/null || true
cp -r "$CLAUDE_DIR/CLAUDE.md" "$BACKUP_DIR/" 2>/dev/null || true
echo "    [1/3] backed up settings.json + CLAUDE.md"

# 2. hooks/agents/skills symlink (Phase 2-5에서 실제 파일 추가됨)
for sub in hooks agents skills; do
    mkdir -p "$INFRA_DIR/$sub"
    if [ -L "$CLAUDE_DIR/$sub-infra" ]; then
        rm "$CLAUDE_DIR/$sub-infra"
    fi
    ln -s "$INFRA_DIR/$sub" "$CLAUDE_DIR/$sub-infra"
done
echo "    [2/3] symlinks: $CLAUDE_DIR/{hooks,agents,skills}-infra → $INFRA_DIR/{hooks,agents,skills}"

# 3. CLAUDE.md/settings.json 패치는 sentinel 라인 사이만 교체
# (실제 패치는 Phase 1 Task 1.5 에서 적용)
echo "    [3/3] CLAUDE.md/settings.json patch — Task 1.5에서 수동 적용"

echo "==> done"
```

- [ ] **Step 2: uninstall.sh 작성**

```bash
#!/usr/bin/env bash
set -euo pipefail

CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"

echo "==> agent-infra uninstaller"
for sub in hooks agents skills; do
    if [ -L "$CLAUDE_DIR/$sub-infra" ]; then
        rm "$CLAUDE_DIR/$sub-infra"
        echo "    removed symlink: $CLAUDE_DIR/$sub-infra"
    fi
done

LATEST_BACKUP=$(ls -td "$CLAUDE_DIR/_backups/agent-infra-"* 2>/dev/null | head -1 || true)
if [ -n "$LATEST_BACKUP" ]; then
    cp "$LATEST_BACKUP/settings.json" "$CLAUDE_DIR/" 2>/dev/null || true
    cp "$LATEST_BACKUP/CLAUDE.md" "$CLAUDE_DIR/" 2>/dev/null || true
    echo "    restored CLAUDE.md/settings.json from: $LATEST_BACKUP"
fi
echo "==> done"
```

- [ ] **Step 3: 실행 권한 부여 + 시범 실행**

```bash
chmod +x install.sh uninstall.sh
./install.sh
ls -la ~/.claude/hooks-infra ~/.claude/agents-infra ~/.claude/skills-infra
```

Expected: 세 symlink가 `~/agent-infra/{hooks,agents,skills}` 를 가리킴.

- [ ] **Step 4: Commit**

```bash
git add install.sh uninstall.sh
git commit -m "feat(install): scaffold install.sh + uninstall.sh with symlink + backup"
```

### Task 1.5: ~/.claude/CLAUDE.md 개편

**Files:**
- Modify: `~/.claude/CLAUDE.md`

- [ ] **Step 1: 기존 CLAUDE.md 끝에 sentinel 블록 추가**

기존 5조항(Karpathy)은 유지하고, 그 아래에 추가:

```markdown

<!-- BEGIN agent-infra -->
## 6. Deploy 정책

- **나는 직접 `git commit` 또는 `git push` 를 실행하지 않는다.** 사용자의 명시적 요청이 있을 때만 진행한다.
- Deploy 전 `/deploy-precheck` 스킬을 호출해 secret leak, 개인 문서 포함, 하드코딩된 시크릿을 검사한다.
- `git commit` 또는 `git push` 시도는 `deploy-guard.sh` hook이 가로채며, precheck 토큰이 없으면 차단된다.

## 7. 페르소나 라우팅

작업 영역별로 다음과 같이 위임한다:

- **기획**: `superpowers:brainstorming` → `superpowers:writing-plans`
- **코드베이스**: `superpowers:subagent-driven-development`. 각 sub-agent 종료 시 CLAUDE.md 재확인.
- **QA**: `qa-agent` sub-agent (Playwright MCP)
- **Review**: `/integrity-review` 스킬 (code-review → review-agent 체인)
- **Deploy**: `/deploy-precheck` 스킬
- **회고**: `SessionEnd` hook이 자동 분석 → feedback 메모리 초안 제안

페르소나 영역을 벗어나는 요청을 받으면 사용자에게 적절한 페르소나로 전환할지 묻는다.

## 8. 문서화 어조

- 한국어 평서체. 짧고 단호. 불필요한 형용사 제거.
- 코드/명령/파일 경로는 inline code 표기.
- 표는 비교가 필요할 때만 사용. 1-2개 항목 비교에는 표를 쓰지 않는다.
- 가정·추측은 명시. "~할 것이다" 보다 "~한다" / "~하지 않는다" 우선.

<!-- END agent-infra -->
```

- [ ] **Step 2: 변경 확인**

```bash
grep -A1 "BEGIN agent-infra" ~/.claude/CLAUDE.md
```

Expected: BEGIN sentinel 라인이 나오고, 그 아래에 "## 6. Deploy 정책" 라인.

- [ ] **Step 3: Claude Code 재시작 후 정상 로드 확인**

사용자가 직접:
1. 현재 Claude Code 세션 종료
2. 새 세션 시작
3. `cat ~/.claude/CLAUDE.md | head -50` 으로 라인 수가 늘었는지 확인

### Task 1.6: settings.json에서 karpathy 플러그인 비활성화

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: enabledPlugins 수정**

기존:
```json
"enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "andrej-karpathy-skills@karpathy-skills": true,
    ...
}
```

변경 후:
```json
"enabledPlugins": {
    "superpowers@claude-plugins-official": true,
    "andrej-karpathy-skills@karpathy-skills": false,
    ...
}
```

- [ ] **Step 2: 변경 확인**

```bash
jq '.enabledPlugins."andrej-karpathy-skills@karpathy-skills"' ~/.claude/settings.json
```

Expected: `false`

- [ ] **Step 3: Claude Code 재시작 후 스킬 목록에서 karpathy-guidelines 사라졌는지 확인**

새 세션에서 `/help` 또는 스킬 목록 명령으로 karpathy-guidelines 가 보이지 않는지 확인. CLAUDE.md의 5조항은 그대로 작동.

### Task 1.7: Phase 1 종료 — 회고

- [ ] **Step 1: 변경사항 종합 커밋**

agent-infra 디렉토리:

```bash
cd ~/agent-infra
git add -A
git status  # 변경 없으면 skip
```

- [ ] **Step 2: ~/.claude/ 백업 확인**

```bash
ls -la ~/.claude/_backups/agent-infra-* | head -1
```

Expected: phase 1 시작 시 만든 백업 존재.

- [ ] **Step 3: Phase 1 종료 조건 확인 (verifiable)**

다음 모두 통과해야 Phase 2 진입:

1. `claude` 재시작 시 CLAUDE.md 정상 로드 (오류 메시지 없음)
2. 기존 작업 regression 없음 (간단한 `ls`, `grep` 명령 정상 작동)
3. `jq '.enabledPlugins."andrej-karpathy-skills@karpathy-skills"' ~/.claude/settings.json` = `false`
4. `ls -la ~/.claude/{hooks,agents,skills}-infra` 모두 symlink 존재

---

## Phase 2: 감시 hooks (위험도 중, silent-fail 필수)

목표: 자동 감시·경고 hook 4개 설치. 모두 `exit 0` 보장, stderr만 로그.
종료 조건: 4개 hook 모두 test fixture로 통과, 정상 워크플로우 차단 없음.

### Task 2.1: 공통 로깅 라이브러리 작성

**Files:**
- Create: `~/agent-infra/hooks/lib/log.sh`

- [ ] **Step 1: log.sh 작성**

```bash
#!/usr/bin/env bash
# log.sh — agent-infra hooks 공통 로거
# usage: source "$(dirname "$0")/lib/log.sh" ; ai_log "message"

AI_LOG_FILE="${AI_LOG_FILE:-$HOME/.claude/hooks/.log}"
AI_LOG_DIR="$(dirname "$AI_LOG_FILE")"
mkdir -p "$AI_LOG_DIR"

ai_log() {
    local hook_name="${HOOK_NAME:-unknown}"
    local timestamp
    timestamp=$(date +"%Y-%m-%dT%H:%M:%S")
    printf "[%s] [%s] %s\n" "$timestamp" "$hook_name" "$*" >> "$AI_LOG_FILE"
}

ai_warn() {
    ai_log "WARN: $*"
    printf "%s\n" "$*" >&2
}
```

- [ ] **Step 2: lib/json.sh 작성**

**Files:** Create `~/agent-infra/hooks/lib/json.sh`

```bash
#!/usr/bin/env bash
# json.sh — JSON 파싱 헬퍼 (jq 의존)

ai_json_get() {
    local input="$1"
    local path="$2"
    local default="${3:-}"
    printf "%s" "$input" | jq -r "$path // empty" 2>/dev/null || printf "%s" "$default"
}

ai_have_jq() {
    command -v jq >/dev/null 2>&1
}
```

- [ ] **Step 3: jq 의존성 사전 체크**

```bash
which jq && jq --version
```

Expected: `/usr/local/bin/jq` 또는 `/opt/homebrew/bin/jq` 등. 없으면 `brew install jq`.

- [ ] **Step 4: Commit**

```bash
cd ~/agent-infra
git add hooks/lib/
git commit -m "feat(hooks): add common log + json helpers"
```

### Task 2.2: session-end-retro.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/session-end-retro.sh`
- Create: `~/agent-infra/hooks/tests/session-end-retro.test.sh`

- [ ] **Step 1: session-end-retro.sh 작성**

```bash
#!/usr/bin/env bash
# session-end-retro.sh — 세션 종료 시 transcript 정량 분석 → feedback 메모리 초안

set +e  # silent fail
export HOOK_NAME="session-end-retro"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
SESSION_ID=$(ai_json_get "$INPUT" '.session_id' 'unknown')
TRANSCRIPT_PATH=$(ai_json_get "$INPUT" '.transcript_path' '')

ai_log "start session_id=$SESSION_ID transcript=$TRANSCRIPT_PATH"

if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
    ai_log "no transcript, skipping"
    exit 0
fi

PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
MEMORY_DIR="$PROJECT_DIR/memory"
mkdir -p "$MEMORY_DIR"

# 정량 분석: jsonl 파싱
PY_SCRIPT=$(cat <<'PYEOF'
import json, sys, re
from collections import Counter

transcript = sys.argv[1]
session_id = sys.argv[2]

read_files = Counter()
tool_errors = 0
verify_keywords = 0

with open(transcript) as f:
    for line in f:
        try:
            evt = json.loads(line)
        except json.JSONDecodeError:
            continue
        tool = evt.get('tool_name') or evt.get('toolName')
        if tool == 'Read':
            path = (evt.get('tool_input') or {}).get('file_path')
            if path:
                read_files[path] += 1
        if evt.get('error') or evt.get('is_error'):
            tool_errors += 1
        text = json.dumps(evt)
        verify_keywords += len(re.findall(r'\b(verified|verifying|verify)\b', text, re.I))

dup_reads = [(f, n) for f, n in read_files.items() if n >= 3]
if not dup_reads and tool_errors < 3 and verify_keywords < 1:
    sys.exit(99)  # 임팩트 없음

print(f"session: {session_id}")
print(f"duplicate_reads: {dup_reads}")
print(f"tool_errors: {tool_errors}")
print(f"verify_keywords: {verify_keywords}")
PYEOF
)

ANALYSIS=$(python3 -c "$PY_SCRIPT" "$TRANSCRIPT_PATH" "$SESSION_ID" 2>>"$AI_LOG_FILE")
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 99 ]; then
    ai_log "no significant patterns, skipping draft"
    exit 0
fi

if [ "$EXIT_CODE" -ne 0 ]; then
    ai_log "python analysis failed"
    exit 0
fi

# DRAFT 메모리 생성
SLUG=$(date +"%Y%m%d-%H%M%S")
DRAFT_FILE="$MEMORY_DIR/feedback-retro-$SLUG-DRAFT.md"

cat > "$DRAFT_FILE" <<EOF
---
name: feedback-retro-$SLUG
description: "세션 자동 회고 초안 — 사용자 검토 후 확정/폐기"
metadata:
  type: feedback
  status: draft
  session_id: $SESSION_ID
---

# 자동 회고 초안

다음 패턴이 이번 세션에서 감지되었습니다. 의미 있는 신호인지 검토 후 확정/폐기하세요.

$ANALYSIS

**다음 액션**:
- 확정 시: 이 파일에서 \`-DRAFT\` 제거하고 MEMORY.md 인덱스에 추가
- 폐기 시: 이 파일 삭제
EOF

ai_log "draft created: $DRAFT_FILE"
exit 0
```

- [ ] **Step 2: 실행 권한 부여**

```bash
chmod +x ~/agent-infra/hooks/session-end-retro.sh
```

- [ ] **Step 3: 테스트 fixture 작성**

**Files:** Create `~/agent-infra/hooks/tests/fixtures/session-end-input.json` and `~/agent-infra/hooks/tests/fixtures/transcript-with-patterns.jsonl`

`session-end-input.json`:
```json
{
  "session_id": "test-session-001",
  "transcript_path": "/tmp/agent-infra-test/transcript.jsonl"
}
```

`transcript-with-patterns.jsonl`:
```json
{"tool_name":"Read","tool_input":{"file_path":"/tmp/a.txt"}}
{"tool_name":"Read","tool_input":{"file_path":"/tmp/a.txt"}}
{"tool_name":"Read","tool_input":{"file_path":"/tmp/a.txt"}}
{"tool_name":"Bash","is_error":true}
{"tool_name":"Bash","is_error":true}
{"tool_name":"Bash","is_error":true}
{"role":"assistant","content":"verified the fix"}
```

- [ ] **Step 4: test 스크립트 작성**

**Files:** Create `~/agent-infra/hooks/tests/session-end-retro.test.sh`

```bash
#!/usr/bin/env bash
# Test: session-end-retro.sh
set -e

INFRA_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
TEST_DIR="/tmp/agent-infra-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR/memory"

# transcript 복사
cp "$(dirname "$0")/fixtures/transcript-with-patterns.jsonl" "$TEST_DIR/transcript.jsonl"

# input 작성 (transcript_path 절대경로)
INPUT='{"session_id":"test-session-001","transcript_path":"'$TEST_DIR/transcript.jsonl'"}'

# hook 실행
printf "%s" "$INPUT" | "$INFRA_DIR/hooks/session-end-retro.sh"

# DRAFT 파일 생성 확인
DRAFT=$(ls "$TEST_DIR/memory/"feedback-retro-*-DRAFT.md 2>/dev/null | head -1)
if [ -z "$DRAFT" ]; then
    echo "FAIL: DRAFT not created"
    exit 1
fi

# 내용 검증
if ! grep -q "duplicate_reads" "$DRAFT"; then
    echo "FAIL: duplicate_reads missing from draft"
    exit 1
fi

if ! grep -q "tool_errors: 3" "$DRAFT"; then
    echo "FAIL: tool_errors count missing"
    exit 1
fi

echo "PASS: session-end-retro.sh"
rm -rf "$TEST_DIR"
```

- [ ] **Step 5: 테스트 실행**

```bash
chmod +x ~/agent-infra/hooks/tests/session-end-retro.test.sh
~/agent-infra/hooks/tests/session-end-retro.test.sh
```

Expected: `PASS: session-end-retro.sh`

- [ ] **Step 6: Commit**

```bash
cd ~/agent-infra
git add hooks/session-end-retro.sh hooks/tests/
git commit -m "feat(hooks): add session-end-retro with quantitative transcript analysis"
```

### Task 2.3: session-start-retro-alert.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/session-start-retro-alert.sh`
- Create: `~/agent-infra/hooks/tests/session-start-retro-alert.test.sh`

- [ ] **Step 1: hook 스크립트 작성**

```bash
#!/usr/bin/env bash
# session-start-retro-alert.sh — 시작 시 직전 DRAFT 회고 목록 알림

set +e
export HOOK_NAME="session-start-retro-alert"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
CWD=$(ai_json_get "$INPUT" '.cwd' "$PWD")

ai_log "start cwd=$CWD"

# 메모리 디렉토리 찾기 (~/.claude/projects/<dir>/memory/)
PROJECT_KEY=$(printf "%s" "$CWD" | sed 's|/|-|g' | sed 's|^-||' | sed 's|^|-|')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"

if [ ! -d "$MEMORY_DIR" ]; then
    ai_log "no memory dir for project, skip"
    exit 0
fi

DRAFTS=$(ls "$MEMORY_DIR"/feedback-retro-*-DRAFT.md 2>/dev/null || true)

if [ -z "$DRAFTS" ]; then
    ai_log "no DRAFT files, skip"
    exit 0
fi

COUNT=$(printf "%s\n" "$DRAFTS" | wc -l | tr -d ' ')
printf "\n📋 [agent-infra] 직전 세션 회고 초안 %s개:\n" "$COUNT" >&2
while IFS= read -r f; do
    [ -z "$f" ] && continue
    printf "   - %s\n" "$(basename "$f")" >&2
done <<< "$DRAFTS"
printf "   확정/폐기는 해당 파일을 직접 편집하세요.\n\n" >&2

exit 0
```

- [ ] **Step 2: 실행 권한 + 테스트**

```bash
chmod +x ~/agent-infra/hooks/session-start-retro-alert.sh
```

테스트 스크립트:

```bash
#!/usr/bin/env bash
# session-start-retro-alert.test.sh
set -e
TEST_PROJ="/tmp/agent-infra-startup-test"
PROJECT_KEY=$(printf "%s" "$TEST_PROJ" | sed 's|/|-|g' | sed 's|^-||' | sed 's|^|-|')
MEMORY_DIR="$HOME/.claude/projects/$PROJECT_KEY/memory"

mkdir -p "$TEST_PROJ"
mkdir -p "$MEMORY_DIR"
touch "$MEMORY_DIR/feedback-retro-test1-DRAFT.md"
touch "$MEMORY_DIR/feedback-retro-test2-DRAFT.md"

INPUT='{"cwd":"'$TEST_PROJ'"}'
OUT=$(printf "%s" "$INPUT" | $(cd "$(dirname "$0")/.." && pwd)/session-start-retro-alert.sh 2>&1 >/dev/null)

if ! echo "$OUT" | grep -q "회고 초안 2개"; then
    echo "FAIL: alert message missing"
    rm -rf "$MEMORY_DIR" "$TEST_PROJ"
    exit 1
fi

echo "PASS: session-start-retro-alert.sh"
rm -rf "$MEMORY_DIR" "$TEST_PROJ"
```

- [ ] **Step 3: 테스트 실행 + Commit**

```bash
chmod +x ~/agent-infra/hooks/tests/session-start-retro-alert.test.sh
~/agent-infra/hooks/tests/session-start-retro-alert.test.sh
cd ~/agent-infra
git add hooks/session-start-retro-alert.sh hooks/tests/session-start-retro-alert.test.sh
git commit -m "feat(hooks): add session-start-retro-alert"
```

### Task 2.4: doc-sprawl-warn.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/doc-sprawl-warn.sh`
- Create: `~/agent-infra/hooks/tests/doc-sprawl-warn.test.sh`

- [ ] **Step 1: hook 작성**

```bash
#!/usr/bin/env bash
# doc-sprawl-warn.sh — PostToolUse(Write): 같은 dir에 md 5개 이상이면 정리 권유

set +e
export HOOK_NAME="doc-sprawl-warn"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

THRESHOLD="${AI_DOC_SPRAWL_THRESHOLD:-5}"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
FILE=$(ai_json_get "$INPUT" '.tool_input.file_path' '')

ai_log "tool=$TOOL file=$FILE"

# Write만, md만
if [ "$TOOL" != "Write" ]; then exit 0; fi
case "$FILE" in
    *.md|*.markdown) ;;
    *) exit 0 ;;
esac

DIR=$(dirname "$FILE")
COUNT=$(find "$DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | wc -l | tr -d ' ')

if [ "$COUNT" -ge "$THRESHOLD" ]; then
    printf "\n📁 [agent-infra] %s 에 .md 파일이 %s개 누적되었습니다. 정리/그루핑을 고려하세요.\n\n" "$DIR" "$COUNT" >&2
    ai_log "sprawl detected: dir=$DIR count=$COUNT"
fi

exit 0
```

- [ ] **Step 2: 테스트 작성**

```bash
#!/usr/bin/env bash
# doc-sprawl-warn.test.sh
set -e
TEST_DIR="/tmp/agent-infra-sprawl-test"
rm -rf "$TEST_DIR"
mkdir -p "$TEST_DIR"

# 4개 md 생성 → 5번째 Write 시 경고
for i in 1 2 3 4; do touch "$TEST_DIR/a$i.md"; done

# 5번째 Write 이벤트
INPUT='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_DIR/a5.md'"}}'
touch "$TEST_DIR/a5.md"

OUT=$(printf "%s" "$INPUT" | $(cd "$(dirname "$0")/.." && pwd)/doc-sprawl-warn.sh 2>&1)

if ! echo "$OUT" | grep -q "정리/그루핑"; then
    echo "FAIL: sprawl warning missing"
    rm -rf "$TEST_DIR"
    exit 1
fi

# 임계 미달 케이스: 단일 파일
TEST_DIR2="/tmp/agent-infra-sprawl-test2"
rm -rf "$TEST_DIR2"
mkdir -p "$TEST_DIR2"
touch "$TEST_DIR2/only.md"
INPUT2='{"tool_name":"Write","tool_input":{"file_path":"'$TEST_DIR2/only.md'"}}'
OUT2=$(printf "%s" "$INPUT2" | $(cd "$(dirname "$0")/.." && pwd)/doc-sprawl-warn.sh 2>&1)

if echo "$OUT2" | grep -q "정리/그루핑"; then
    echo "FAIL: false positive on single-md dir"
    exit 1
fi

echo "PASS: doc-sprawl-warn.sh"
rm -rf "$TEST_DIR" "$TEST_DIR2"
```

- [ ] **Step 3: 실행 권한 + 테스트 + Commit**

```bash
chmod +x ~/agent-infra/hooks/doc-sprawl-warn.sh ~/agent-infra/hooks/tests/doc-sprawl-warn.test.sh
~/agent-infra/hooks/tests/doc-sprawl-warn.test.sh
cd ~/agent-infra
git add hooks/doc-sprawl-warn.sh hooks/tests/doc-sprawl-warn.test.sh
git commit -m "feat(hooks): add doc-sprawl-warn"
```

### Task 2.5: persona-drift-warn.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/persona-drift-warn.sh`
- Create: `~/agent-infra/hooks/tests/persona-drift-warn.test.sh`

- [ ] **Step 1: hook 작성**

```bash
#!/usr/bin/env bash
# persona-drift-warn.sh — UserPromptSubmit: 한 prompt에 다영역 키워드 혼재 시 페르소나 분리 권유

set +e
export HOOK_NAME="persona-drift-warn"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
PROMPT=$(ai_json_get "$INPUT" '.prompt' '')

if [ -z "$PROMPT" ]; then exit 0; fi

# 영역별 키워드
matches=()
echo "$PROMPT" | grep -qiE '기획|brainstorm|design|spec|prd' && matches+=("기획")
echo "$PROMPT" | grep -qiE '구현|implement|코드|작성|refactor' && matches+=("코드")
echo "$PROMPT" | grep -qiE 'qa|테스트|screenshot|playwright|버그리포트' && matches+=("QA")
echo "$PROMPT" | grep -qiE 'review|리뷰|의존성|트랜잭션|무결성' && matches+=("Review")
echo "$PROMPT" | grep -qiE 'deploy|배포|commit|push|환경변수' && matches+=("Deploy")

COUNT=${#matches[@]}
ai_log "matched persona=${matches[*]} count=$COUNT"

if [ "$COUNT" -ge 3 ]; then
    printf "\n🎭 [agent-infra] 이 prompt에 영역 %s가 섞여 있습니다: %s\n" "$COUNT개" "${matches[*]}"  >&2
    printf "   페르소나 단계별 분리를 권장합니다(기획→코드→QA→Review→Deploy).\n\n" >&2
fi

exit 0
```

- [ ] **Step 2: 테스트 작성**

```bash
#!/usr/bin/env bash
# persona-drift-warn.test.sh
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/persona-drift-warn.sh"

# Case 1: 단일 영역 → 경고 없음
OUT1=$(printf '{"prompt":"버그 좀 고쳐줘"}' | "$HOOK" 2>&1)
if echo "$OUT1" | grep -q "페르소나"; then
    echo "FAIL: false positive on single-domain prompt"
    exit 1
fi

# Case 2: 3 영역 혼재 → 경고
P='{"prompt":"기획부터 설계하고 코드 구현 후 QA까지 한 번에 처리해줘"}'
OUT2=$(printf "%s" "$P" | "$HOOK" 2>&1)
if ! echo "$OUT2" | grep -q "페르소나 단계별 분리"; then
    echo "FAIL: drift not detected"
    exit 1
fi

echo "PASS: persona-drift-warn.sh"
```

- [ ] **Step 3: 실행 권한 + 테스트 + Commit**

```bash
chmod +x ~/agent-infra/hooks/persona-drift-warn.sh ~/agent-infra/hooks/tests/persona-drift-warn.test.sh
~/agent-infra/hooks/tests/persona-drift-warn.test.sh
cd ~/agent-infra
git add hooks/persona-drift-warn.sh hooks/tests/persona-drift-warn.test.sh
git commit -m "feat(hooks): add persona-drift-warn"
```

### Task 2.6: settings.json에 hook 4개 등록

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: 현재 settings.json 백업**

```bash
cp ~/.claude/settings.json ~/.claude/_backups/agent-infra-phase2-pre.json
```

- [ ] **Step 2: settings.json 수정 — `hooks` 객체에 4개 추가**

기존 `hooks.UserPromptSubmit` 배열의 `hooks` 안에 새 hook 추가, 신규 `SessionStart`, `SessionEnd`, `PostToolUse` 추가. 결과 예시:

```json
"hooks": {
  "UserPromptSubmit": [
    { "hooks": [
        { "type": "command", "command": "..." },
        { "type": "command", "command": "$HOME/agent-infra/hooks/persona-drift-warn.sh" }
    ]}
  ],
  "PreToolUse": [...],
  "PostToolUse": [
    { "matcher": "Write",
      "hooks": [
        { "type": "command", "command": "$HOME/agent-infra/hooks/doc-sprawl-warn.sh" }
      ]}
  ],
  "SessionStart": [
    { "hooks": [
        { "type": "command", "command": "$HOME/agent-infra/hooks/session-start-retro-alert.sh" }
    ]}
  ],
  "SessionEnd": [
    { "hooks": [
        { "type": "command", "command": "$HOME/agent-infra/hooks/session-end-retro.sh" }
    ]}
  ],
  "Stop": [...]
}
```

- [ ] **Step 3: JSON 유효성 검사**

```bash
jq '.hooks' ~/.claude/settings.json | head -50
```

Expected: 새 hook 4개가 매핑되어 보임. 파싱 에러 없음.

- [ ] **Step 4: Claude Code 재시작 후 hook 동작 확인 (사용자 수동)**

새 세션에서:
- 새 md 파일 5개 만들어 doc-sprawl 알림 확인
- 3 영역 혼재 prompt 입력해서 persona-drift 알림 확인
- 세션 종료 후 다음 세션 시작 시 retro-alert 동작 확인 (DRAFT 존재 시)

### Task 2.7: Phase 2 종료

- [ ] **Step 1: 종료 조건 verification 표 작성**

`~/agent-infra/docs/reports/deploy/2026-06-10-phase2-validation.md` 작성:

```markdown
# Phase 2 Validation

| Hook | Test 결과 | 실환경 동작 확인 |
|---|---|---|
| session-end-retro | PASS | (수동) |
| session-start-retro-alert | PASS | (수동) |
| doc-sprawl-warn | PASS | (수동) |
| persona-drift-warn | PASS | (수동) |
| settings.json `jq` 파싱 | PASS | |
| 정상 워크플로우 차단 없음 | (수동 확인) | |
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add docs/reports/deploy/
git commit -m "docs: phase 2 validation report"
```

---

## Phase 3: 행위 가드 hooks (위험도 중-고)

목표: 상태 변경 동반 hook 3개 설치 (TASK 체크박스 토글, sub-agent 종료 알림, deploy 차단).

### Task 3.1: task-checkbox-sync.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/task-checkbox-sync.sh`
- Create: `~/agent-infra/hooks/tests/task-checkbox-sync.test.sh`

- [ ] **Step 1: hook 작성**

```bash
#!/usr/bin/env bash
# task-checkbox-sync.sh — PostToolUse(Edit/Write): 활성 [T-NNN] 토글

set +e
export HOOK_NAME="task-checkbox-sync"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
FILE=$(ai_json_get "$INPUT" '.tool_input.file_path' '')

if [ "$TOOL" != "Edit" ] && [ "$TOOL" != "Write" ]; then exit 0; fi
if [ -z "$FILE" ]; then exit 0; fi

# 프로젝트 루트 찾기 (git root, fallback: cwd)
ROOT=$(cd "$(dirname "$FILE")" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")

# 활성 task ID 찾기: docs/plans/*.md 의 frontmatter active_task
ACTIVE_TASK=""
for plan in "$ROOT/docs/plans/"*.md; do
    [ -f "$plan" ] || continue
    ACTIVE_TASK=$(awk '/^---$/{n++; next} n==1 && /^active_task:/{gsub(/^active_task:[ ]*/,""); print; exit}' "$plan")
    [ -n "$ACTIVE_TASK" ] && break
done

if [ -z "$ACTIVE_TASK" ]; then
    ai_log "no active_task found, skip file=$FILE"
    exit 0
fi

# 활성 task ID로 TASK 파일 찾기
TASK_FILE=""
for tf in "$ROOT/docs/tasks/"*.md; do
    [ -f "$tf" ] || continue
    if grep -q "\[$ACTIVE_TASK\]" "$tf"; then TASK_FILE="$tf"; break; fi
done

if [ -z "$TASK_FILE" ]; then
    ai_log "active task $ACTIVE_TASK referenced but no TASK file contains it"
    exit 0
fi

# `- [ ] [T-NNN]` → `- [x] [T-NNN]`
TMP=$(mktemp)
sed "s/^\(- \[\) \(\] \[$ACTIVE_TASK\]\)/\1x\2/" "$TASK_FILE" > "$TMP" && mv "$TMP" "$TASK_FILE"

ai_log "toggled $ACTIVE_TASK in $TASK_FILE"
exit 0
```

- [ ] **Step 2: 테스트 작성**

```bash
#!/usr/bin/env bash
# task-checkbox-sync.test.sh
set -e

HOOK="$(cd "$(dirname "$0")/.." && pwd)/task-checkbox-sync.sh"
SANDBOX="/tmp/agent-infra-task-sync-test"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/docs/plans" "$SANDBOX/docs/tasks" "$SANDBOX/src"
cd "$SANDBOX"
git init -q

cat > docs/plans/feature.md <<'EOF'
---
title: 테스트
active_task: T-042
---
plan body
EOF

cat > docs/tasks/feature.md <<'EOF'
- [ ] [T-041] 이미 끝낸 것
- [ ] [T-042] 활성 작업
- [ ] [T-043] 다음 작업
EOF

# Edit 이벤트 시뮬레이션
INPUT='{"tool_name":"Edit","tool_input":{"file_path":"'$SANDBOX/src/foo.ts'"}}'
printf "%s" "$INPUT" | "$HOOK"

# 결과 확인
if ! grep -q '^\- \[x\] \[T-042\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-042 not toggled to [x]"
    cat "$SANDBOX/docs/tasks/feature.md"
    exit 1
fi

# T-041 / T-043 은 변경 없어야 함
if grep -q '^\- \[x\] \[T-041\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-041 incorrectly toggled"
    exit 1
fi
if grep -q '^\- \[x\] \[T-043\]' "$SANDBOX/docs/tasks/feature.md"; then
    echo "FAIL: T-043 incorrectly toggled"
    exit 1
fi

echo "PASS: task-checkbox-sync.sh"
rm -rf "$SANDBOX"
```

- [ ] **Step 3: 실행 권한 + 테스트 + Commit**

```bash
chmod +x ~/agent-infra/hooks/task-checkbox-sync.sh ~/agent-infra/hooks/tests/task-checkbox-sync.test.sh
~/agent-infra/hooks/tests/task-checkbox-sync.test.sh
cd ~/agent-infra
git add hooks/task-checkbox-sync.sh hooks/tests/task-checkbox-sync.test.sh
git commit -m "feat(hooks): add task-checkbox-sync"
```

### Task 3.2: subagent-reload-claude.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/subagent-reload-claude.sh`
- Create: `~/agent-infra/hooks/tests/subagent-reload-claude.test.sh`

- [ ] **Step 1: hook 작성**

```bash
#!/usr/bin/env bash
# subagent-reload-claude.sh — SubagentStop: 메인에 CLAUDE.md 재확인 안내

set +e
export HOOK_NAME="subagent-reload-claude"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
AGENT=$(ai_json_get "$INPUT" '.agent_name' 'unknown')

ai_log "subagent ended: $AGENT"
printf "\n🔁 [agent-infra] sub-agent '%s' 종료. 다음 루프 시작 전 CLAUDE.md 정책을 재확인하세요.\n\n" "$AGENT" >&2
exit 0
```

- [ ] **Step 2: 테스트 작성**

```bash
#!/usr/bin/env bash
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/subagent-reload-claude.sh"
OUT=$(printf '{"agent_name":"qa-agent"}' | "$HOOK" 2>&1)
if ! echo "$OUT" | grep -q "qa-agent"; then
    echo "FAIL: agent name not in output"
    exit 1
fi
if ! echo "$OUT" | grep -q "CLAUDE.md"; then
    echo "FAIL: CLAUDE.md mention missing"
    exit 1
fi
echo "PASS: subagent-reload-claude.sh"
```

- [ ] **Step 3: 실행 권한 + 테스트 + Commit**

```bash
chmod +x ~/agent-infra/hooks/subagent-reload-claude.sh ~/agent-infra/hooks/tests/subagent-reload-claude.test.sh
~/agent-infra/hooks/tests/subagent-reload-claude.test.sh
cd ~/agent-infra
git add hooks/subagent-reload-claude.sh hooks/tests/subagent-reload-claude.test.sh
git commit -m "feat(hooks): add subagent-reload-claude"
```

### Task 3.3: deploy-guard.sh hook 작성

**Files:**
- Create: `~/agent-infra/hooks/deploy-guard.sh`
- Create: `~/agent-infra/hooks/tests/deploy-guard.test.sh`

- [ ] **Step 1: hook 작성**

```bash
#!/usr/bin/env bash
# deploy-guard.sh — PreToolUse(Bash): git commit/push 차단, deploy-precheck 토큰 검증

set +e
export HOOK_NAME="deploy-guard"

INFRA_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$INFRA_DIR/lib/log.sh"
source "$INFRA_DIR/lib/json.sh"

INPUT=$(cat)
TOOL=$(ai_json_get "$INPUT" '.tool_name' '')
CMD=$(ai_json_get "$INPUT" '.tool_input.command' '')

if [ "$TOOL" != "Bash" ]; then exit 0; fi

# git commit / git push 패턴 체크
if ! echo "$CMD" | grep -qE '\bgit\s+(commit|push)\b'; then
    exit 0
fi

ai_log "intercepted: $CMD"

# precheck 토큰 검증
ROOT=$(git -C "$PWD" rev-parse --show-toplevel 2>/dev/null || echo "")
if [ -z "$ROOT" ]; then
    DENY_REASON="현재 디렉토리가 git repo가 아닙니다."
else
    TOKEN_FILE=""
    for f in "$ROOT/.claude/.deploy-token-"*; do
        [ -f "$f" ] || continue
        # 30분 유효성
        AGE=$(($(date +%s) - $(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null || echo 0)))
        if [ "$AGE" -lt 1800 ]; then TOKEN_FILE="$f"; break; fi
    done
    if [ -n "$TOKEN_FILE" ]; then
        ai_log "token valid: $TOKEN_FILE"
        exit 0
    fi
    DENY_REASON="deploy-precheck 토큰이 없거나 만료됨. \`/deploy-precheck\` 스킬을 먼저 호출하세요."
fi

# permission deny 응답
jq -n --arg reason "$DENY_REASON" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $reason
  }
}'
exit 0
```

- [ ] **Step 2: 테스트 작성**

```bash
#!/usr/bin/env bash
set -e
HOOK="$(cd "$(dirname "$0")/.." && pwd)/deploy-guard.sh"
SANDBOX="/tmp/agent-infra-deploy-guard-test"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/.claude"
cd "$SANDBOX"
git init -q

# Case 1: 토큰 없음 → deny
OUT=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}' | "$HOOK")
if ! echo "$OUT" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL: should deny without token"
    echo "$OUT"
    exit 1
fi

# Case 2: 유효한 토큰 → 통과 (출력 없음)
touch "$SANDBOX/.claude/.deploy-token-abc123"
OUT2=$(printf '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo"}}' | "$HOOK")
if [ -n "$OUT2" ]; then
    echo "FAIL: should be silent with valid token (got: $OUT2)"
    exit 1
fi

# Case 3: git status는 통과 (commit/push 아님)
OUT3=$(printf '{"tool_name":"Bash","tool_input":{"command":"git status"}}' | "$HOOK")
if [ -n "$OUT3" ]; then
    echo "FAIL: git status should not be blocked"
    exit 1
fi

# Case 4: 만료된 토큰 (31분 전 mtime)
rm "$SANDBOX/.claude/.deploy-token-abc123"
touch -t "$(date -v-31M +%Y%m%d%H%M)" "$SANDBOX/.claude/.deploy-token-old" 2>/dev/null || \
  touch -d "31 minutes ago" "$SANDBOX/.claude/.deploy-token-old"
OUT4=$(printf '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | "$HOOK")
if ! echo "$OUT4" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null; then
    echo "FAIL: expired token should still deny"
    exit 1
fi

echo "PASS: deploy-guard.sh"
rm -rf "$SANDBOX"
```

- [ ] **Step 3: 실행 권한 + 테스트 + Commit**

```bash
chmod +x ~/agent-infra/hooks/deploy-guard.sh ~/agent-infra/hooks/tests/deploy-guard.test.sh
~/agent-infra/hooks/tests/deploy-guard.test.sh
cd ~/agent-infra
git add hooks/deploy-guard.sh hooks/tests/deploy-guard.test.sh
git commit -m "feat(hooks): add deploy-guard with precheck token verification"
```

### Task 3.4: settings.json 갱신 — Phase 3 hook 등록

**Files:**
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: 백업**

```bash
cp ~/.claude/settings.json ~/.claude/_backups/agent-infra-phase3-pre.json
```

- [ ] **Step 2: 다음 변경 적용**

`hooks.PostToolUse` 배열에 `Edit` matcher 추가, 기존 `Write` matcher에는 task-checkbox-sync도 추가:

```json
"PostToolUse": [
  {
    "matcher": "Write",
    "hooks": [
      { "type": "command", "command": "$HOME/agent-infra/hooks/doc-sprawl-warn.sh" },
      { "type": "command", "command": "$HOME/agent-infra/hooks/task-checkbox-sync.sh" }
    ]
  },
  {
    "matcher": "Edit",
    "hooks": [
      { "type": "command", "command": "$HOME/agent-infra/hooks/task-checkbox-sync.sh" }
    ]
  }
]
```

`hooks.PreToolUse` 에 Bash matcher 추가:

```json
"PreToolUse": [
  {
    "matcher": "Read",
    "hooks": [ ... 기존 ... ]
  },
  {
    "matcher": "Bash",
    "hooks": [
      { "type": "command", "command": "$HOME/agent-infra/hooks/deploy-guard.sh" }
    ]
  }
]
```

신규 `SubagentStop` 추가:

```json
"SubagentStop": [
  { "hooks": [
    { "type": "command", "command": "$HOME/agent-infra/hooks/subagent-reload-claude.sh" }
  ]}
]
```

- [ ] **Step 3: JSON 유효성 + 새 세션 동작 확인**

```bash
jq '.hooks' ~/.claude/settings.json
```

새 세션에서:
- 더미 git 디렉토리에서 `git commit` 시도 → 차단 메시지 확인
- 더미 `[T-001]` 토글 확인 (Edit 발생 시)

### Task 3.5: Phase 3 종료 — validation 리포트

- [ ] **Step 1: 리포트 작성**

`~/agent-infra/docs/reports/deploy/2026-06-10-phase3-validation.md`:

```markdown
# Phase 3 Validation

| Hook | Test | 실환경 |
|---|---|---|
| task-checkbox-sync | PASS | (수동) |
| subagent-reload-claude | PASS | (수동) |
| deploy-guard | PASS (4 case) | (수동) |
| settings.json 갱신 | PASS | |
| `git commit` 차단 확인 | (수동) | |
| `[T-XXX]` 토글 확인 | (수동) | |
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add -A
git commit -m "docs: phase 3 validation report"
```

---

## Phase 4: Sub-agents (위험도 중, 권한 설정 검증 필수)

목표: qa-agent · review-agent 정의 및 권한 설정. Sandbox 더미 webapp으로 통합 테스트.

### Task 4.1: Playwright MCP 사전 점검

**Files:** (변경 없음 — 환경 확인만)

- [ ] **Step 1: 설치 여부 확인**

```bash
claude mcp list 2>/dev/null | grep -i playwright || echo "NOT INSTALLED"
```

- [ ] **Step 2: 미설치 시 사용자에게 설치 안내**

설치 명령:
```bash
claude mcp add playwright -s user -- npx '@playwright/mcp@latest'
```

설치 후 다음 세션에서 `mcp__playwright__*` 도구 사용 가능.

### Task 4.2: qa-agent.md 작성

**Files:**
- Create: `~/agent-infra/agents/qa-agent.md`

- [ ] **Step 1: agent 파일 작성**

```markdown
---
name: qa-agent
description: TASK.md 기반으로 웹앱을 실제로 조작하며 시나리오를 수행, 스크린샷과 버그 리포트를 산출. 호출 시 반드시 검토 대상 feature 이름과 URL을 명시할 것.
tools: Read, Write, mcp__playwright__navigate, mcp__playwright__click, mcp__playwright__fill, mcp__playwright__screenshot, mcp__playwright__wait_for_selector, mcp__playwright__evaluate, mcp__playwright__console_messages
---

# QA Agent

## 책임

`docs/tasks/<feature>.md` 의 체크박스를 읽고, 각 항목에 대응하는 시나리오를 Playwright로 수행한다. 화면 스크린샷과 버그 리포트를 산출.

## 작업 순서

1. **준비**
   - 입력으로 받은 `feature` 이름과 base URL을 확인
   - `docs/tasks/<feature>.md` 를 읽어 `[T-NNN]` 단위 시나리오 추출
   - 출력 디렉토리 생성: `docs/reports/qa/<YYYY-MM-DD>-<feature>/screenshots/`

2. **시나리오 실행 (각 [T-NNN] 단위)**
   - `mcp__playwright__navigate` 로 페이지 진입
   - 입력/클릭은 `mcp__playwright__fill`, `mcp__playwright__click`
   - 검증 포인트마다 `mcp__playwright__screenshot` → `<task-id>-<step>.png`
   - 콘솔 오류는 `mcp__playwright__console_messages` 로 수집

3. **버그 발견 시**
   - `.counters.json` 의 `bug` 카운터를 읽어 `[B-NNN]` 생성
   - `docs/reports/bugs/<B-NNN>-<slug>.md` 에 reproduction step + 스크린샷 경로 기록
   - 카운터 +1 저장

4. **종료 리포트**
   - `docs/reports/qa/<YYYY-MM-DD>-<feature>.md` 작성. 구조:
     - 환경(URL, browser, viewport)
     - 시나리오별 PASS/FAIL 표
     - 발견 버그 ID 목록
     - 스크린샷 파일 경로 목록

## 제한

- 코드 수정 금지 (Edit 미허용)
- git 명령 금지
- Bash 도구 미허용 — Playwright MCP만 사용
- Write는 `docs/reports/qa/`, `docs/reports/bugs/` path 한정

## 실패 모드

- Playwright MCP 미설치: 즉시 종료하고 사용자에게 `claude mcp add playwright` 안내
- base URL 응답 없음: 3회 retry 후 종료, "URL 응답 없음" 리포트
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add agents/qa-agent.md
git commit -m "feat(agents): add qa-agent persona"
```

### Task 4.3: review-agent.md 작성

**Files:**
- Create: `~/agent-infra/agents/review-agent.md`

- [ ] **Step 1: agent 파일 작성**

```markdown
---
name: review-agent
description: code-review 스킬 출력 위에 의존성 방향 · 트랜잭션 정합성 · 무결성 · 유지보수성 · 확장성 · CLAUDE.md 컨벤션 준수를 검토. 치명 버그 발견 시 verdict=reject.
tools: Read, Bash
---

# Review Agent

## 책임

1단계 `code-review` 스킬 출력을 입력으로 받아, 다음 7개 차원에서 추가 검토 후 verdict를 발행한다.

## 입력

- `code-review` 스킬 결과 (JSON)
- `git diff <base>...HEAD` 출력
- `~/.claude/CLAUDE.md` (글로벌 컨벤션)
- 프로젝트 루트의 `.claude/CLAUDE.md` (있다면)
- `docs/specs/` 의 최근 spec (가장 최근 1개)

## 검토 차원

1. **의존성 방향**: import / require 그래프에서 레이어 룰(예: 도메인 → 인프라 단일 방향)을 어기는 변경이 있는가
2. **트랜잭션 정합성**: atomic boundary 외부에서 상태 변경, 부분 실패 시 rollback 부재
3. **무결성**: DB constraint 우회, referential integrity 누락
4. **유지보수성**: 함수 길이/복잡도 급증, 결합도 상승, 책임 다중화
5. **확장성**: 확장 포인트 부재, 하드코딩, OCP 위반
6. **CLAUDE.md 컨벤션 준수**: 글로벌·프로젝트 컨벤션 둘 다 체크
7. **치명 버그 가능성**: 데이터 손실, 보안 취약점, 런타임 crash 가능 경로

## 출력 (structured)

```json
{
  "verdict": "approve" | "reject",
  "critical": true | false,
  "findings": [
    {
      "dimension": "의존성|트랜잭션|무결성|유지보수성|확장성|컨벤션|치명버그",
      "severity": "info|warning|critical",
      "file": "src/foo.ts:42",
      "summary": "...",
      "fix_hint": "..."
    }
  ],
  "summary": "한 문단 종합 의견"
}
```

## 판정 룰

- `critical: true` 이면 자동으로 `verdict: "reject"`
- Critical 트리거: 다음 중 하나라도 해당
  - 데이터 손실 가능성 (DROP/TRUNCATE/DELETE WITHOUT WHERE, 파일 비동기 삭제)
  - 보안 취약점 (XSS/SQLi/CSRF 미방어, 시크릿 하드코딩, 인증 우회 분기)
  - 런타임 crash 가능 경로 (명백한 null deref, 무한 루프)
  - 의존성 방향 위반 (프로젝트 CLAUDE.md 레이어 룰 어김)
  - 트랜잭션 무결성 깨짐
- 그 외: warning/info finding은 발행하되 verdict=approve 가능

## 제한

- Write/Edit 금지 — 검토만, 수정 안 함
- `git commit/push/rm/mv/mkdir` 금지 — `git diff/log/show` 한정
- `code-review` 스킬을 한 번 더 호출하지 않음 (이미 입력으로 받음)
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add agents/review-agent.md
git commit -m "feat(agents): add review-agent persona with structured output schema"
```

### Task 4.4: install.sh 갱신 — agents symlink + permissions

**Files:**
- Modify: `~/agent-infra/install.sh`
- Modify: `~/.claude/settings.json`

- [ ] **Step 1: install.sh 의 symlink 단계 확장**

`for sub in hooks agents skills` 루프는 이미 있음. 다음을 추가:

```bash
# 4. agents/* 를 ~/.claude/agents/ 에 개별 symlink (Claude Code는 ~/.claude/agents/ 직접 스캔)
mkdir -p "$CLAUDE_DIR/agents"
for agent in "$INFRA_DIR/agents/"*.md; do
    [ -f "$agent" ] || continue
    NAME=$(basename "$agent")
    if [ -L "$CLAUDE_DIR/agents/$NAME" ]; then
        rm "$CLAUDE_DIR/agents/$NAME"
    fi
    ln -s "$agent" "$CLAUDE_DIR/agents/$NAME"
done
echo "    [4/N] linked agents/*.md"
```

- [ ] **Step 2: install.sh 재실행**

```bash
~/agent-infra/install.sh
ls -la ~/.claude/agents/qa-agent.md ~/.claude/agents/review-agent.md
```

Expected: 두 symlink 모두 존재.

- [ ] **Step 3: settings.json 의 `permissions` 영역에 sub-agent 권한 명시**

(Claude Code의 permissions 모델이 sub-agent 별 권한 지원 시) — 현재는 frontmatter `tools` 필드가 권한 한정이므로 step 3은 frontmatter 검증으로 대체:

```bash
head -5 ~/.claude/agents/qa-agent.md ~/.claude/agents/review-agent.md
```

Expected: 각 파일 frontmatter에 `tools:` 리스트가 spec과 일치.

- [ ] **Step 4: Commit**

```bash
cd ~/agent-infra
git add install.sh
git commit -m "feat(install): symlink agents/*.md into ~/.claude/agents/"
```

### Task 4.5: E2E sandbox 더미 webapp 생성

**Files:**
- Create: `~/agent-infra/tests/e2e-sandbox/`

- [ ] **Step 1: 더미 앱 디렉토리 만들기**

```bash
mkdir -p ~/agent-infra/tests/e2e-sandbox
cd ~/agent-infra/tests/e2e-sandbox
```

- [ ] **Step 2: 정적 HTML 1 페이지로 최소 webapp 생성**

`index.html`:
```html
<!doctype html>
<html lang="ko"><head><meta charset="utf-8"><title>QA Sandbox</title></head>
<body>
  <h1>회원가입</h1>
  <form id="signup">
    <label>이메일 <input id="email" type="email" required></label>
    <label>비밀번호 <input id="pwd" type="password" required minlength="8"></label>
    <button type="submit">가입</button>
  </form>
  <p id="msg"></p>
  <script>
    document.getElementById('signup').addEventListener('submit', e => {
      e.preventDefault();
      const email = document.getElementById('email').value;
      const pwd = document.getElementById('pwd').value;
      const msg = document.getElementById('msg');
      // 의도된 버그: 비밀번호 8자 미만도 통과시킴 (minlength HTML5 우회)
      msg.textContent = `OK: ${email}`;
      msg.style.color = 'green';
    });
  </script>
</body></html>
```

- [ ] **Step 3: 더미 TASK.md + plan**

`tests/e2e-sandbox/docs/tasks/signup.md`:
```markdown
- [ ] [T-001] 이메일 빈 값 입력 시 가입 차단
- [ ] [T-002] 비밀번호 8자 미만 입력 시 가입 차단
- [ ] [T-003] 정상 입력 시 "OK: <email>" 메시지 표시
```

`tests/e2e-sandbox/docs/plans/signup.md`:
```markdown
---
title: 회원가입 sandbox
active_task: T-002
---
sandbox webapp for E2E test
```

- [ ] **Step 4: 로컬 서버 실행 + 즉시 종료 (사용자 메모)**

E2E 실행 시 다음으로 서버 띄움 — 자동화 불필요, 메모만:

```bash
cd ~/agent-infra/tests/e2e-sandbox && python3 -m http.server 8090
```

- [ ] **Step 5: Commit**

```bash
cd ~/agent-infra
git add tests/e2e-sandbox/
git commit -m "test(e2e): add sandbox webapp + dummy tasks/plan"
```

### Task 4.6: qa-agent 실환경 검증

**Files:** (실행만)

- [ ] **Step 1: 로컬 서버 실행**

```bash
cd ~/agent-infra/tests/e2e-sandbox && python3 -m http.server 8090 &
SERVER_PID=$!
sleep 1
```

- [ ] **Step 2: 메인 Claude 세션에서 qa-agent 호출**

(사용자 수동) Claude Code에서:
```
@qa-agent 다음을 QA 해줘:
- feature: signup
- URL: http://localhost:8090
- TASK: ~/agent-infra/tests/e2e-sandbox/docs/tasks/signup.md
```

Expected:
- `~/agent-infra/tests/e2e-sandbox/docs/reports/qa/<date>-signup.md` 생성
- 스크린샷 디렉토리 생성
- T-002 시나리오에서 버그 발견 → `[B-001]` 생성

- [ ] **Step 3: 서버 종료**

```bash
kill $SERVER_PID
```

- [ ] **Step 4: 결과 확인**

```bash
ls ~/agent-infra/tests/e2e-sandbox/docs/reports/qa/
ls ~/agent-infra/tests/e2e-sandbox/docs/reports/bugs/
```

### Task 4.7: review-agent 실환경 검증

**Files:** (실행만)

- [ ] **Step 1: 의도된 트랜잭션 버그가 있는 더미 diff 작성**

```bash
mkdir -p /tmp/review-sandbox && cd /tmp/review-sandbox
git init -q
cat > .claude/CLAUDE.md <<'EOF'
# Project conventions

- 도메인 레이어는 인프라(DB/HTTP)를 직접 호출하지 않는다 (역방향 금지)
- 모든 상태 변경은 트랜잭션 boundary 안에서.
EOF
mkdir -p src/domain src/infra
cat > src/domain/order.ts <<'EOF'
// 의도된 위반: domain → infra 직접 import
import { db } from '../infra/db';
export async function createOrder(o) {
  await db.insert(o);  // 트랜잭션 없음
  await db.notify(o);  // 부분 실패 가능
}
EOF
cat > src/infra/db.ts <<'EOF'
export const db = { insert: async (o)=>{}, notify: async (o)=>{} };
EOF
git add -A && git commit -q -m "init"
# 위반 diff 만들기 — 위 파일은 이미 init된 상태이므로 추가 변경
```

- [ ] **Step 2: 메인 Claude에서 review-agent 호출**

(수동) Claude Code에서:
```
@review-agent 다음을 검토해줘:
- 프로젝트: /tmp/review-sandbox
- diff: HEAD~1..HEAD
- code-review 결과는 먼저 /code-review 스킬로 확보 후 첨부
```

Expected output 형식:
```json
{
  "verdict": "reject",
  "critical": true,
  "findings": [
    {"dimension":"의존성","severity":"critical","file":"src/domain/order.ts:2","summary":"domain → infra 역방향 import","fix_hint":"..."},
    {"dimension":"트랜잭션","severity":"critical","file":"src/domain/order.ts:4-5","summary":"insert/notify 사이 트랜잭션 없음","fix_hint":"..."}
  ],
  "summary": "..."
}
```

### Task 4.8: Phase 4 종료 리포트

- [ ] **Step 1: 리포트 작성**

`~/agent-infra/docs/reports/deploy/2026-06-10-phase4-validation.md`:

```markdown
# Phase 4 Validation

| 항목 | 결과 |
|---|---|
| Playwright MCP 설치 | (확인) |
| qa-agent frontmatter `tools` 권한 | spec 일치 |
| review-agent frontmatter `tools` 권한 | spec 일치 |
| install.sh symlink agents | PASS |
| qa-agent E2E (sandbox webapp) | PASS — T-002 버그 [B-001] 생성 |
| review-agent E2E (의도된 위반) | PASS — verdict=reject, critical=true |
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add docs/reports/deploy/
git commit -m "docs: phase 4 validation report"
```

---

## Phase 5: 커스텀 Skills (위험도 낮음)

목표: `/integrity-review` 와 `/deploy-precheck` 두 스킬을 작성하고 ~/.claude/skills/ 로 symlink.

### Task 5.1: integrity-review 스킬 작성

**Files:**
- Create: `~/agent-infra/skills/integrity-review/SKILL.md`

- [ ] **Step 1: SKILL.md 작성**

```markdown
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
```

- [ ] **Step 2: Commit**

```bash
cd ~/agent-infra
git add skills/integrity-review/
git commit -m "feat(skills): add integrity-review chaining skill"
```

### Task 5.2: deploy-precheck 스킬 작성

**Files:**
- Create: `~/agent-infra/skills/deploy-precheck/SKILL.md`
- Create: `~/agent-infra/skills/deploy-precheck/scripts/precheck.sh`

- [ ] **Step 1: SKILL.md 작성**

```markdown
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
```

- [ ] **Step 2: precheck.sh 스크립트 작성**

```bash
#!/usr/bin/env bash
# precheck.sh — deploy-precheck 검사 로직
set +e

MODE="${1:-staged}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "ERROR: not a git repo"; exit 2; }
cd "$ROOT"

# 대상 파일 산정
if [ "$MODE" = "all" ]; then
    FILES=$(git ls-files; git ls-files --others --exclude-standard)
else
    FILES=$(git diff --cached --name-only)
fi
FILES=$(echo "$FILES" | sort -u | grep -v '^$')

# ignore 패턴
IGNORE_FILE=".claude/deploy-precheck.ignore"
filter_ignored() {
    if [ -f "$IGNORE_FILE" ]; then
        grep -vFf "$IGNORE_FILE"
    else
        cat
    fi
}

FILES=$(echo "$FILES" | filter_ignored)

# 1. 토큰 자체 leak 방지
if echo "$FILES" | grep -qE '\.claude/\.deploy-token-'; then
    echo "CRITICAL: deploy token file is in commit candidates"
    exit 3
fi

# 2. 개인 문서 경로
PRIV_HITS=$(echo "$FILES" | grep -E '\.local\.md$|^plans/|^notes/|^scratch/' || true)

# 3. secret 파일 경로
SECRET_PATH_HITS=$(echo "$FILES" | grep -E '\.env$|\.env\.|\.pem$|\.key$|\.p12$|\.pfx$|^secrets/|^credentials/' | grep -v '\.env\.example$' || true)

# 4. 내용 검사 — secret regex
SECRET_PATTERN='(API[_-]?KEY|SECRET[_-]?KEY|ACCESS[_-]?TOKEN|PRIVATE[_-]?KEY|PASSWORD|BEARER)\s*[:=]\s*["'"'"'][^"'"'"']{12,}'
CONTENT_HITS=""
while IFS= read -r f; do
    [ -z "$f" ] || [ ! -f "$f" ] && continue
    HIT=$(grep -nE "$SECRET_PATTERN" "$f" 2>/dev/null || true)
    if [ -n "$HIT" ]; then
        CONTENT_HITS="$CONTENT_HITS\n$f:\n$HIT"
    fi
done <<< "$FILES"

# 5. 하드코딩 — process.env / os.environ 패턴 부재 + literal secret
# (간소화: 위 4번이 dotenv 사용 안 함을 어느 정도 잡음)

# 종합
if [ -n "$PRIV_HITS$SECRET_PATH_HITS$CONTENT_HITS" ]; then
    echo "=== deploy-precheck: 차단됨 ==="
    [ -n "$PRIV_HITS" ] && { echo ""; echo "[개인 문서 경로]"; echo "$PRIV_HITS"; }
    [ -n "$SECRET_PATH_HITS" ] && { echo ""; echo "[Secret 파일 경로]"; echo "$SECRET_PATH_HITS"; }
    [ -n "$CONTENT_HITS" ] && { echo ""; echo "[하드코딩된 시크릿 패턴]"; echo -e "$CONTENT_HITS"; }
    echo ""
    echo "위 항목을 제거/이동/.gitignore 처리 후 재시도하세요."
    exit 1
fi

# 통과 → 토큰 생성
SHA=$(echo "$FILES" | shasum -a 256 | cut -c1-12)
mkdir -p .claude
TOKEN_FILE=".claude/.deploy-token-$SHA"
touch "$TOKEN_FILE"
echo "=== deploy-precheck: 통과 ==="
echo "토큰: $TOKEN_FILE (30분 유효)"
exit 0
```

- [ ] **Step 3: 실행 권한**

```bash
chmod +x ~/agent-infra/skills/deploy-precheck/scripts/precheck.sh
```

- [ ] **Step 4: 단위 테스트 sandbox**

```bash
SANDBOX="/tmp/precheck-sandbox"
rm -rf "$SANDBOX" && mkdir -p "$SANDBOX" && cd "$SANDBOX"
git init -q

# Case 1: 깨끗한 staged → 통과
echo 'export const HELLO = "world"' > a.ts
git add a.ts
~/agent-infra/skills/deploy-precheck/scripts/precheck.sh staged
ls .claude/.deploy-token-* || { echo "FAIL: token not created"; exit 1; }

# Case 2: .env staged → 차단
echo 'API_KEY=abcd1234efgh5678' > .env
git add .env
RESULT=$(~/agent-infra/skills/deploy-precheck/scripts/precheck.sh staged || true)
if ! echo "$RESULT" | grep -q "차단됨"; then echo "FAIL: should block .env"; exit 1; fi

# Case 3: 하드코딩
echo 'const API_KEY = "sk-veryverysecretvalue12345"' > b.ts
git add b.ts
RESULT2=$(~/agent-infra/skills/deploy-precheck/scripts/precheck.sh staged || true)
if ! echo "$RESULT2" | grep -q "하드코딩"; then echo "FAIL: should detect hardcoded secret"; exit 1; fi

echo "PASS: deploy-precheck (3 cases)"
rm -rf "$SANDBOX"
```

- [ ] **Step 5: Commit**

```bash
cd ~/agent-infra
git add skills/deploy-precheck/
git commit -m "feat(skills): add deploy-precheck with token issuance"
```

### Task 5.3: install.sh 갱신 — skills symlink

**Files:**
- Modify: `~/agent-infra/install.sh`

- [ ] **Step 1: skills 디렉토리 개별 symlink 추가**

기존 `for sub in hooks agents skills` 루프는 그대로 (`skills-infra` symlink 만들었음). 추가로 Claude Code가 `~/.claude/skills/` 에서 개별 디렉토리 스캔하므로 각 skill 폴더도 symlink:

```bash
# 5. skills/<name>/ 를 ~/.claude/skills/<name>/ 로 개별 symlink
mkdir -p "$CLAUDE_DIR/skills"
for skill in "$INFRA_DIR/skills/"*/; do
    [ -d "$skill" ] || continue
    NAME=$(basename "$skill")
    if [ -L "$CLAUDE_DIR/skills/$NAME" ]; then
        rm "$CLAUDE_DIR/skills/$NAME"
    fi
    ln -s "$skill" "$CLAUDE_DIR/skills/$NAME"
done
echo "    [5/N] linked skills/*/"
```

- [ ] **Step 2: install.sh 재실행 + 검증**

```bash
~/agent-infra/install.sh
ls -la ~/.claude/skills/integrity-review ~/.claude/skills/deploy-precheck
```

Expected: 두 symlink 존재, 각자 `~/agent-infra/skills/...` 가리킴.

- [ ] **Step 3: Claude Code 재시작 후 스킬 인식 확인**

새 세션에서 `/integrity-review`, `/deploy-precheck` 가 스킬 목록에 나타나는지 확인.

- [ ] **Step 4: Commit**

```bash
cd ~/agent-infra
git add install.sh
git commit -m "feat(install): symlink skills/*/ into ~/.claude/skills/"
```

### Task 5.4: 통합 E2E 시나리오 실행

**Files:** (실행만)

- [ ] **Step 1: 가상 feature "signup" 6단계 통과**

(사용자 수동, 새 세션) 다음을 차례로 실행해서 산출물 9종이 모두 생성되는지 확인:

1. `/brainstorming` → signup feature 설계 → `docs/specs/<date>-signup.md`
2. (사용자가 PRD 작성 요청) → `docs/prd/signup.md`
3. `/writing-plans` → `docs/plans/signup.md` (frontmatter `active_task: T-001`)
4. plan에서 task 추출 → `docs/tasks/signup.md` 에 `[T-001]`, `[T-002]`, `[T-003]`
5. `superpowers:subagent-driven-development` 로 T-001 ~ T-003 구현 → `task-checkbox-sync.sh` hook이 토글 → 모두 `[x]`
6. `@qa-agent` → `docs/reports/qa/<date>-signup.md` + 스크린샷 + `docs/reports/bugs/B-NNN-*.md`
7. `/integrity-review` → `docs/reports/reviews/signup-<date>.md`
8. `/deploy-precheck` → 통과 시 `.claude/.deploy-token-*` 생성, 차단 시 리포트
9. (사용자 직접) `git commit` → `deploy-guard.sh` 가 토큰 확인 후 통과

- [ ] **Step 2: 종료 후 새 세션 시작 시 `session-start-retro-alert.sh` 가 회고 DRAFT 알림**

전 세션에서 발생한 패턴(예: 같은 파일 여러 번 read)이 있으면 `feedback-retro-*-DRAFT.md` 가 있고, 새 세션 시작 시 알림이 뜸.

### Task 5.5: 최종 Phase 5 종료 리포트

- [ ] **Step 1: 리포트 작성**

`~/agent-infra/docs/reports/deploy/2026-06-10-phase5-validation.md`:

```markdown
# Phase 5 Validation — Final

| Skill | Test | 실환경 |
|---|---|---|
| integrity-review SKILL.md | (구조 검토) | (수동) |
| deploy-precheck precheck.sh | PASS (3 case) | (수동) |
| install.sh symlink skills | PASS | |
| E2E signup feature 6단계 | (수동) | |
| 9종 산출물 모두 생성 확인 | (수동) | |
| 회고 DRAFT → 다음 세션 알림 | (수동) | |
```

- [ ] **Step 2: 최종 commit**

```bash
cd ~/agent-infra
git add docs/reports/deploy/
git commit -m "docs: phase 5 + final E2E validation"
git tag -a v0.1.0 -m "agent-infra Phase 5 complete"
```

---

## Self-Review

### Spec 커버리지

| Spec 항목 | 구현 Task |
|---|---|
| D1 단일 통합 spec | Task 0.0 (이미 완료) |
| D2 글로벌+오버라이드 | Task 1.5 (CLAUDE.md) + install.sh symlink 전략 |
| D3 Hybrid 자동화 | Phase 2 (감시 hook) + Phase 3 (행위 가드) + Phase 5 (skill) |
| D4 QA+Review sub-agent | Task 4.2, 4.3 |
| D5 docs/tasks 위치 | Task 1.2 |
| D6 feedback 메모리 제안 | Task 2.2 (session-end-retro) |
| D7 [T-NNN] 매핑 | Task 3.1 (task-checkbox-sync) + Task 1.3 (ID 컨벤션) |
| D8 Playwright MCP | Task 4.1, 4.2 |
| D9 code-review → review-agent | Task 5.1 (integrity-review) |
| D10 docs/ B 옵션 | Task 1.2, 1.3 |
| D11 review-agent 외부 도구 없음 | Task 4.3 (review-agent 단독) |
| D12 ~/agent-infra/ 분리 | Task 0.0, 1.1 |

모든 결정 항목에 대응 Task 존재. **갭 없음.**

### Placeholder 검사

- TBD/TODO: 본문에 없음. ✅
- "implement later": 없음 ✅
- "appropriate error handling": 모든 step에 구체 코드 또는 명령 ✅
- "similar to Task N": 없음 — 각 task 내부에서 코드 복제 ✅

### 타입 일관성

- `[T-NNN]` 표기: Task 1.3, 3.1, 4.5, 5.4 모두 일치 ✅
- `feedback-retro-<slug>-DRAFT.md`: Task 2.2 생성 / Task 2.3 알림 — 파일명 패턴 일치 ✅
- `mcp__playwright__*` 도구명: Task 4.1, 4.2 모두 동일 prefix ✅
- `verdict: "approve"|"reject"`: Task 4.3 (review-agent) / Task 5.1 (integrity-review) 모두 동일 enum ✅

검토 통과.

---

## Execution Handoff

Plan 완성. 다음 두 가지 실행 방식 중 선택:

1. **Subagent-Driven (권장)** — 각 task마다 fresh subagent 디스패치, task 간 메인이 검토, 빠른 반복
2. **Inline Execution** — 현재 세션에서 task batch 실행, checkpoint 지점에서 검토

어느 쪽으로 진행할지 알려주세요.
