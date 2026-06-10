# B-001 비밀번호 길이 JS 검증 누락 (HTML5 minlength 우회 시 8자 미만 가입 통과)

- **발견 시나리오**: [T-002] 비밀번호 8자 미만 입력 시 가입 차단
- **심각도**: Medium (브라우저 HTML5 검증으로 일반 경로는 가려져 있으나, JS 단독으로는 검증 없음)
- **발견 일자**: 2026-06-10
- **환경**: http://localhost:8090, Playwright (Chromium), viewport 기본값

## 재현 단계

일반 사용자 흐름(가입 버튼 클릭)에서는 HTML5 `minlength=8` 가 submit 을 차단하여 `#msg` 가 비어 있음. 그러나 submit 핸들러 자체에는 길이 검증이 없어 다음 우회 경로에서 결함이 노출됨:

1. http://localhost:8090 으로 이동.
2. 이메일에 `test@example.com` 입력.
3. 비밀번호에 `abc1234` (7자) 입력.
4. DevTools / JS 콘솔에서 다음 실행:
   ```js
   const f = document.getElementById('signup');
   f.noValidate = true;
   f.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
   ```
5. `#msg` 텍스트 확인.

## 기대 동작

- 8자 미만 비밀번호는 어떤 경로로도 가입이 통과되지 않아야 함.
- submit 핸들러 내부에서 `pwd.length < 8` 검증 후 에러 메시지를 표시해야 함.

## 실제 동작

- submit 핸들러가 검증 없이 `msg.textContent = `OK: ${email}`` 를 실행.
- `#msg` 가 `OK: test@example.com` (초록색) 으로 표시되어 가입 성공처럼 보임.
- 즉, HTML5 `minlength` 만 방어선이며 JS 단의 검증이 부재.

## 관련 코드

```js
document.getElementById('signup').addEventListener('submit', e => {
  e.preventDefault();
  const email = document.getElementById('email').value;
  const pwd = document.getElementById('pwd').value;
  const msg = document.getElementById('msg');
  // 의도된 버그: 비밀번호 8자 미만도 통과시킴 (minlength HTML5 우회)
  msg.textContent = `OK: ${email}`;
  msg.style.color = 'green';
});
```

## 스크린샷

- /Users/leeseonro/agent-infra/tests/e2e-sandbox/docs/reports/qa/2026-06-10-signup/screenshots/T-002-short-password.png
