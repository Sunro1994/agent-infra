# ai_log gap (SessionStart:startup) 진단 보고서

작성일: 2026-06-11
관련 사이클: Phase 6 (auto-retro 신호 강화와 묶음 진행)
범위: 재현 조건 규명만. 수정은 별도 사이클.

## 배경

Phase 5 종료 직후 `session-start-retro-alert.sh` 수정 과정에서 별건으로 발견. `SessionStart:startup` hook 이 정상 실행됨에도 `ai_log` 에 엔트리가 기록되지 않는 경우가 있었다. Phase 5 당시에는 stdout/stderr 라우팅 문제(B-003)가 주요 수정 대상이었으나, ai_log 누락은 원인이 달라 Phase 6 별도 진단 태스크로 분리했다.

## 재현 harness

`hooks/lib/diag_session_start.sh` — 3가지 환경 조합으로 `session-start-retro-alert.sh` 를 실행하고 exit code, stdout, stderr, ai_log delta 를 각각 측정한다.

**harness 한계**: SAMPLE_INPUT 이 cwd 를 `hooks/` 로 고정하므로, hook 내부의 "no memory dir for project, skip" 경로가 항상 실행된다. 정상/stripped 환경의 ai_log delta=2 는 `start cwd=...` + `no memory dir for project, skip` 두 엔트리에 해당하며, 실제 SessionStart 동작의 전체 엔트리 수와 다를 수 있다. 단, 첫 번째 엔트리(`start cwd=...`)가 존재하는지 여부 자체는 로깅 가능 여부 판단에 유효하다.

### 환경별 결과

| Env | `$HOME` | `AI_LOG_FILE` | exit | stdout | ai_log delta |
| --- | --- | --- | --- | --- | --- |
| normal | `/Users/leeseonro` | `/Users/leeseonro/.claude/hooks/.log` | 0 | 0b | 2 |
| stripped | `/Users/leeseonro` | `/Users/leeseonro/.claude/hooks/.log` | 0 | 0b | 2 |
| no_home | (unset) | `/.claude/hooks/.log` | 0 | 0b | 0 |

**no_home stderr:**
```
mkdir: /.claude: Read-only file system
/Users/leeseonro/agent-infra/hooks/lib/log.sh: line 12: /.claude/hooks/.log: No such file or directory
/Users/leeseonro/agent-infra/hooks/lib/log.sh: line 12: /.claude/hooks/.log: No such file or directory
```

## 가설 검증

### 1. `$HOME` unset → `AI_LOG_FILE` 권한 실패

판정: **YES — 확인됨**. Phase 7 T1 commit `cd8fa48` 로 fix 완료.

`lib/log.sh:5` 에서 `AI_LOG_FILE="${AI_LOG_FILE:-$HOME/.claude/hooks/.log}"` 로 기본값을 설정한다. `$HOME` 이 비어 있으면 `AI_LOG_FILE=/.claude/hooks/.log` 로 해석된다. `no_home` 환경에서 `mkdir: /.claire: Read-only file system` 오류가 실제로 발생했고, ai_log delta=0 으로 엔트리가 하나도 기록되지 않았다. OS 루트 파일시스템 읽기 전용으로 인한 로깅 전면 실패다.

### 2. `mkdir -p` silent fail + `>>` append silent

판정: **PARTIAL — 조건부 YES**. Phase 7 T1 commit `cd8fa48` 로 fix 완료 (HOME fallback + write retry).

`lib/log.sh:6` 의 `mkdir -p "$(dirname "$AI_LOG_FILE")"` 는 실패 시 중단하지 않는다(`|| return` 없음). `lib/log.sh:12` 의 `printf ... >> "$AI_LOG_FILE"` 도 실패를 반환하지 않는다. harness 에서는 stderr 를 캡처했기 때문에 오류 메시지가 보였지만, 실제 `SessionStart:startup` launcher 가 stderr 를 `/dev/null` 로 리다이렉트하거나 suppression 할 경우 오류 메시지는 완전히 사라지고 로그 누락만 남는다. 즉, **launcher 의 stderr 처리 방식에 따라 이 silent failure 가 진짜 불가시 갭이 된다.**

### 3. Launcher 가 `AI_LOG_FILE` 을 override

판정: **NO — 관찰 데이터로 기각**

Phase 7 T6 instrument 로 실제 `SessionStart:startup` 환경변수를 캡처 (`$HOME/.claude/hooks/diag/*session-start-retro-alert.env`). 캡처된 4개 세션 모두에서 `AI_LOG_FILE` 변수 자체가 env 에 부재. launcher 가 override 하지 않음이 관찰로 확인됨.

### 4. stdout/stderr 라우팅 차이로 인한 불가시

판정: **UNVERIFIED — ENV-NOT-OBSERVED**

env 캡처만으로는 stdout/stderr 의 실제 라우팅을 관측할 수 없다. Phase 7 T6 instrument 의 범위 밖. 직접 검증하려면 `exec >$tmp_out 2>$tmp_err` 류의 별도 trace 가 필요하다. Phase 8 후보로 명시.

## 추정 root cause

`$HOME` 이 unset 인 환경(또는 `AI_LOG_FILE` 이 명시적으로 지정되지 않은 환경)에서 기본 경로가 `/.claude/hooks/.log` 로 해석되고, OS 루트 파일시스템이 읽기 전용이므로 `mkdir -p` 와 `printf >>` 모두 실패한다. 실패 코드가 전파되지 않고, launcher 가 stderr 를 흡수할 경우 오류 징후도 남지 않는다. **가설 1 + 가설 2 의 조합**이 현재 확인 가능한 root cause 이다.

`SessionStart:startup` launcher 가 `$HOME` 을 정상 설정하는지, `AI_LOG_FILE` 을 override 하는지는 미확인 상태다.

## Phase 7 관찰 결과

- **캡처 세션 수**: 4 (instrument 활성 후 SessionStart fire 4회)
- **분석 일시**: 2026-06-11
- **캡처 위치**: `$HOME/.claude/hooks/diag/*session-start-retro-alert.env`

### HOME 변형 분포

| HOME 값 | 세션 수 |
| --- | --- |
| `/Users/leeseonro` (정상) | 4 |
| empty (`HOME=`) | 0 |
| unset | 0 |

실제 `SessionStart:startup` 환경에서 `HOME` 이 비어 있거나 unset 인 케이스는 관찰되지 않았다. 가설 1·2 는 합성 환경 (`diag_session_start.sh` no_home) 에서만 재현된다.

### T1 fix 의 효과

T1 (`lib/log.sh` HOME fallback + write retry, commit `cd8fa48`) 적용 이후 모든 캡처 세션에서 `ai_log` 정상 기록 확인. T1 은 실제 관찰된 결함이 아니라 합성 환경에서 발견된 잠재 결함에 대한 defensive fix 로 분류된다.

### 부가 관찰

- 최초 캡처 (11:39, ts=1781145556) 에는 `CLAUDE_PROJECT_DIR` 누락, PATH 에 plugin paths (`superpowers`, `token-optimizer`, `understand-anything`) 포함. 이후 세션부터는 `CLAUDE_PROJECT_DIR` 가 설정됨.
- 한 세션 (11:48, ts=1781146130) 의 `CLAUDE_PROJECT_DIR=/Users/leeseonro` 로, 부모 디렉토리에서 시작된 세션. agent-infra 가 아닌 컨텍스트에서도 동일 hook 이 호출됨을 확인.

## 후속 사이클 작업 제안

1. **fix**: `lib/log.sh:6` 에 `|| { echo "ai_log: mkdir failed" >&2; return 1; }` 추가. `mkdir -p` 실패 시 즉시 중단.
2. **fix**: `lib/log.sh:12` `printf` 실패 시 명시적 경고 출력.
3. **verify**: `SessionStart:startup` hook 에 `env > /tmp/ss-env-$$.txt` 임시 삽입 후 실제 fire 시 환경변수 덤프. 가설 3, 4 검증.
4. **harness 개선**: `diag_session_start.sh` 의 SAMPLE_INPUT cwd 를 프로젝트 루트로 수정해 "no memory dir" 경로 bypass. 실제 full-path 실행을 재현하도록 수정.
