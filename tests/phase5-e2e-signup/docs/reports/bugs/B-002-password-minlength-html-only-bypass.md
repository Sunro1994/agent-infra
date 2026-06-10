# B-002 비밀번호 길이 검증이 HTML5 minlength 에만 의존

- **Severity**: high
- **Feature**: signup
- **Related Task**: T-002 (KD-2)

## 요약

비밀번호 길이 검증이 `<input minlength="8">` 속성만으로 수행된다. DOM 조작 또는 HTML5 검증을 지원하지 않는 클라이언트에서는 4자 이하 비밀번호도 제출이 가능하다. JS 측 검증이 누락되어 있다.

## Reproduction Steps

1. `http://127.0.0.1:8000/` 접속.
2. DevTools 콘솔에서 `document.getElementById('pwd').removeAttribute('minlength')` 실행.
3. 이메일 input 에 `test@example.com` 입력.
4. 비밀번호 input 에 `1234` (4자) 입력.
5. `가입` 버튼 클릭.

## Expected

비밀번호가 8자 미만이므로 가입이 차단되어야 한다 (서버 또는 JS 측 검증).

## Actual

`OK: test@example.com` 초록색 성공 메시지가 노출된다. JS submit 핸들러 내부에 길이 검증이 없다.

## Evidence

- Screenshot: `../qa/2026-06-11-signup/screenshots/T-002-kd2-minlength-bypass.png`

## 추정 원인

- 파일: `tests/phase5-e2e-signup/index.html`
- 라인: 약 24-31 (`form.addEventListener('submit', ...)`)
- submit 핸들러에 `if (pwd.length < 8) { showError(...); return; }` 누락. 서버측 검증도 함께 도입 필요.
