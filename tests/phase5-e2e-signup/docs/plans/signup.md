---
title: signup feature implementation plan
active_task: T-001
spec: docs/specs/2026-06-10-signup.md
prd: docs/prd/signup.md
---

# Signup Feature Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** agent-infra Phase 5 E2E 검증용 단일 페이지 signup 폼을 구현한다. 3개의 의도된 결함(KD-1/2/3)을 포함한다.

**Architecture:** 단일 `index.html` 파일에 embedded `<style>`, `<script>`. 백엔드 없음. file:// 또는 `python3 -m http.server` 로 즉시 동작.

**Tech Stack:** HTML5, 바닐라 JavaScript. 외부 라이브러리·빌드 도구 없음.

**Reference:**
- Spec: [`docs/specs/2026-06-10-signup.md`](../specs/2026-06-10-signup.md)
- PRD: [`docs/prd/signup.md`](../prd/signup.md)

**Verification 정책**: 단일 정적 HTML 이므로 단위 테스트 프레임워크를 끼우지 않는다. 각 task 의 verification step 은 (a) `grep` 으로 코드 패턴 존재 확인, (b) 브라우저 실시간 동작은 Step 6 의 qa-agent + Playwright MCP 에 위임한다. 이는 spec §1 의 "no build, no framework" 제약에 따른 의도된 단순화다.

---

## File Structure

| 파일 | 책임 |
|---|---|
| `index.html` | 단일 페이지. form + JS validator + 결과 메시지. T-001~T-003 모두 이 파일을 수정한다. |
| `docs/tasks/signup.md` | task 체크박스 리스트. 본 plan 작성 직후 별도 단계(Step 4)에서 생성. `task-checkbox-sync.sh` hook 이 토글 대상. |

작은 feature 이므로 파일을 쪼개지 않는다. 모든 변경은 `index.html` 한 파일에 누적된다.

---

## Task 1: T-001 — 이메일 형식 검증 + base form 스캐폴드

**Files:**
- Create: `tests/phase5-e2e-signup/index.html`

**의도된 결함 (KD-1):** 정규식이 `/@/` 로 느슨하다. `a@b` 같은 입력이 통과한다. QA Step 6 에서 B-001 로 잡혀야 한다.

- [ ] **Step 1.1: index.html 신규 생성 — 폼 스캐폴드 + 이메일 검증**

다음 내용으로 `tests/phase5-e2e-signup/index.html` 를 생성한다.

```html
<!doctype html>
<html lang="ko">
<head>
  <meta charset="utf-8">
  <title>회원가입</title>
  <style>
    body { font-family: sans-serif; max-width: 320px; margin: 2rem auto; }
    label { display: block; margin: 0.5rem 0; }
    input { width: 100%; padding: 0.4rem; }
    button { margin-top: 0.5rem; padding: 0.4rem 1rem; }
    #msg { margin-top: 1rem; min-height: 1.2em; }
  </style>
</head>
<body>
  <h1>회원가입</h1>
  <form id="signup">
    <label>이메일 <input id="email" type="email" required></label>
    <label>비밀번호 <input id="pwd" type="password" required></label>
    <button type="submit">가입</button>
  </form>
  <p id="msg"></p>
  <script>
    const form = document.getElementById('signup');
    const msg = document.getElementById('msg');
    function showError(text) {
      msg.textContent = text;
      msg.style.color = 'red';
    }
    form.addEventListener('submit', e => {
      e.preventDefault();
      const email = document.getElementById('email').value;
      const pwd = document.getElementById('pwd').value;
      // KD-1: 의도된 결함 — '@' 포함 여부만 검사
      if (!/@/.test(email)) {
        showError('이메일 형식이 올바르지 않습니다');
        return;
      }
      msg.textContent = 'TODO: 다음 task 에서 완성';
      msg.style.color = 'gray';
    });
  </script>
</body>
</html>
```

- [ ] **Step 1.2: 파일 패턴 검증**

다음 명령으로 핵심 패턴이 들어갔는지 확인한다.

```bash
cd ~/agent-infra/tests/phase5-e2e-signup
grep -n 'id="email"' index.html
grep -n '/@/' index.html
grep -n 'showError' index.html
```

Expected: 3개 명령 모두 1개 이상 매칭. `/@/` 정규식이 의도된 결함의 핵심이므로 반드시 보이는 위치여야 한다.

- [ ] **Step 1.3: 로컬 브라우저 실행 (스모크)**

```bash
cd ~/agent-infra/tests/phase5-e2e-signup
python3 -m http.server 8000 &
open http://127.0.0.1:8000/
```

수동 확인: 페이지가 로드되고 이메일 필드에 `notanemail` 입력 → 가입 누르면 "이메일 형식이 올바르지 않습니다" 메시지. `a@b` 입력 → "TODO: 다음 task 에서 완성" 회색 메시지. (의도된 결함 KD-1 확인.)

서버 종료: `pkill -f 'python3 -m http.server 8000'`

- [ ] **Step 1.4: tasks 체크박스 토글**

`docs/tasks/signup.md` 의 `[T-001]` 항목을 `[x]` 로 토글한다. (task-checkbox-sync.sh hook 이 자동 처리하는 경우 수동 편집 불필요.)

- [ ] **Step 1.5: 사용자 확인 (commit 은 사용자가 직접)**

이 plan 의 모든 task 가 끝난 시점에 사용자가 직접 `git commit` 을 실행한다. 본 step 에서 commit 하지 않는다.

---

## Task 2: T-002 — 비밀번호 길이 검증 (HTML5 minlength 의존)

**Files:**
- Modify: `tests/phase5-e2e-signup/index.html`

**의도된 결함 (KD-2):** HTML5 `minlength="8"` 만 사용하고 JS submit 핸들러에서는 길이 검증을 누락한다. DevTools 로 `minlength` 속성을 제거하면 우회 가능. QA Step 6 에서 B-002 로 잡혀야 한다.

- [ ] **Step 2.1: 비밀번호 input 에 minlength 속성 추가**

`index.html` 에서 비밀번호 input 라인을 다음으로 변경한다.

찾기:
```html
<label>비밀번호 <input id="pwd" type="password" required></label>
```

바꾸기:
```html
<label>비밀번호 (8자 이상) <input id="pwd" type="password" required minlength="8"></label>
```

JS submit 핸들러는 **수정하지 않는다.** 의도적으로 JS 측 검증을 누락한다 — 이것이 KD-2 의 핵심.

- [ ] **Step 2.2: 파일 패턴 검증**

```bash
cd ~/agent-infra/tests/phase5-e2e-signup
grep -n 'minlength="8"' index.html
grep -c 'pwd.length' index.html
```

Expected:
- 첫 번째 명령: 1 매칭
- 두 번째 명령: `0` (JS 길이 검증이 없음을 확인 — 이것이 의도된 결함 KD-2)

- [ ] **Step 2.3: 로컬 브라우저 실행 (스모크)**

```bash
python3 -m http.server 8000 &
open http://127.0.0.1:8000/
```

수동 확인:
1. `test@example.com` + `1234` 입력 → 브라우저가 "이 텍스트는 8자 이상이어야 합니다" 비슷한 기본 메시지로 차단 (정상 흐름)
2. DevTools 로 `<input id="pwd">` 의 `minlength` 속성 제거 → `1234` 다시 입력 → 가입 누르면 차단되지 않고 통과 (KD-2 우회 시연)

서버 종료: `pkill -f 'python3 -m http.server 8000'`

- [ ] **Step 2.4: tasks 체크박스 토글**

`docs/tasks/signup.md` 의 `[T-002]` 항목을 `[x]` 로 토글한다.

---

## Task 3: T-003 — 성공 메시지 표시 (innerHTML)

**Files:**
- Modify: `tests/phase5-e2e-signup/index.html`

**의도된 결함 (KD-3):** 성공 메시지를 `textContent` 가 아닌 `innerHTML` 로 렌더한다. 이메일 값이 그대로 HTML 로 해석되어 XSS 가능. QA Step 6 에서 B-003 로 잡히고, integrity-review Step 7 에서 코드 레벨 지적이 들어와야 한다.

- [ ] **Step 3.1: 성공 메시지 분기 교체**

`index.html` 의 submit 핸들러 안 임시 메시지 부분을 다음으로 교체한다.

찾기:
```javascript
      msg.textContent = 'TODO: 다음 task 에서 완성';
      msg.style.color = 'gray';
```

바꾸기:
```javascript
      // KD-3: 의도된 결함 — innerHTML 로 사용자 입력을 렌더. XSS.
      msg.innerHTML = 'OK: ' + email;
      msg.style.color = 'green';
```

- [ ] **Step 3.2: 파일 패턴 검증**

```bash
cd ~/agent-infra/tests/phase5-e2e-signup
grep -n 'msg.innerHTML' index.html
grep -c 'TODO' index.html
```

Expected:
- 첫 번째 명령: 1 매칭 (KD-3 의 핵심)
- 두 번째 명령: `0` (Task 1.1 의 임시 TODO 메시지가 제거됨)

- [ ] **Step 3.3: 로컬 브라우저 실행 (스모크)**

```bash
python3 -m http.server 8000 &
open http://127.0.0.1:8000/
```

수동 확인:
1. `test@example.com` + `password123` 입력 → "OK: test@example.com" 초록색 메시지 (정상 흐름)
2. DevTools console 에서 `document.getElementById('email').type='text'` 실행 후 `<img src=x onerror=document.title='XSS'>` 입력 + `password123` → 가입 누르면 페이지 타이틀이 `XSS` 로 변경 (KD-3 시연). 또는 `a@b<img src=x onerror=alert(1)>` 같은 페이로드 직접 시도.

서버 종료: `pkill -f 'python3 -m http.server 8000'`

- [ ] **Step 3.4: tasks 체크박스 토글**

`docs/tasks/signup.md` 의 `[T-003]` 항목을 `[x]` 로 토글한다.

- [ ] **Step 3.5: 최종 검증 — tasks 체크박스 3개 모두 [x]**

```bash
grep -c '\- \[x\]' ~/agent-infra/tests/phase5-e2e-signup/docs/tasks/signup.md
```

Expected: `3`

---

## Post-implementation handoff

Task 3 까지 완료되면 본 plan 의 구현 부분이 끝난다. 이후 단계는 Task 5.4 의 Step 6~9 에서 별도로 실행한다.

- Step 6: `@qa-agent` → QA 리포트 + 스크린샷 + B-001/B-002/B-003 버그 리포트
- Step 7: `/integrity-review` → review 리포트 (innerHTML 지적 기대)
- Step 8: `/deploy-precheck` → 토큰 발급
- Step 9: 사용자가 직접 `git commit`

본 plan 에서는 buggy 코드를 **수정하지 않는다.** 의도된 결함 3개를 유지한 채 종료한다 (spec §6 운영 결정).
