# B-003 성공 메시지 렌더에 innerHTML 사용 (XSS)

- **Severity**: high
- **Feature**: signup
- **Related Task**: T-003 (KD-3)

## 요약

성공 메시지 출력에 `msg.innerHTML = 'OK: ' + email` 을 사용한다. 사용자 입력이 HTML 로 직접 파싱되므로 Stored/Reflected XSS 가 가능하다. 본 테스트에서는 페이지 title 이 `XSS-DETECTED` 로 변경되는 것으로 확인됐다.

## Reproduction Steps

1. `http://127.0.0.1:8000/` 접속.
2. DevTools 콘솔에서 `document.getElementById('email').type='text'` 실행 (HTML5 email 검증 우회).
3. 이메일 input 에 `a@b<img src=x onerror=document.title='XSS-DETECTED'>` 입력.
4. 비밀번호 input 에 `password123` 입력.
5. `가입` 버튼 클릭.
6. 콘솔에서 `document.title` 평가.

## Expected

이메일 문자열이 텍스트로 escape 되어 메시지에 그대로 노출되거나, 또는 유효성 검증으로 차단되어야 한다. 페이지 title 은 `회원가입` 으로 유지되어야 한다.

## Actual

- `<img>` 태그가 DOM 에 삽입되어 `onerror` 핸들러가 실행됨.
- `document.title === 'XSS-DETECTED'` 로 변경됨.
- 콘솔에 `Failed to load resource: 404 ... /x` 기록 (img src 로드 시도 흔적).

## Evidence

- Screenshot: `../qa/2026-06-11-signup/screenshots/T-003-kd3-xss.png`
- `document.title` evaluate 결과: `"XSS-DETECTED"`

## 추정 원인

- 파일: `tests/phase5-e2e-signup/index.html`
- 라인: 약 32 (`msg.innerHTML = 'OK: ' + email;`)
- `innerHTML` 대신 `textContent` 를 사용해야 한다. 또는 안전한 templating/escaping 도입 필요.
