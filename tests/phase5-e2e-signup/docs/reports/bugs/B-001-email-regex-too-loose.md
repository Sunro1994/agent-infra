# B-001 이메일 정규식이 지나치게 느슨함

- **Severity**: high
- **Feature**: signup
- **Related Task**: T-001 (KD-1)

## 요약

이메일 형식 검증이 `/@/.test(email)` 으로만 수행된다. `@` 문자 하나만 포함되면 유효 이메일로 통과하므로 `a@b` 같은 명백히 잘못된 값이 가입 처리된다.

## Reproduction Steps

1. `http://127.0.0.1:8000/` 접속.
2. (HTML5 `type=email` 우회를 위해) DevTools 콘솔에서 `document.getElementById('email').setAttribute('type','text')` 실행.
3. 이메일 input 에 `a@b` 입력.
4. 비밀번호 input 에 `password123` 입력.
5. `가입` 버튼 클릭.

## Expected

`이메일 형식이 올바르지 않습니다` 빨간색 메시지가 노출되고 가입이 차단된다.

## Actual

`OK: a@b` 초록색 성공 메시지가 노출된다.

## Evidence

- Screenshot: `../qa/2026-06-11-signup/screenshots/T-001-kd1-loose-regex.png`

## 추정 원인

- 파일: `tests/phase5-e2e-signup/index.html`
- 라인: 약 26 (`if (!/@/.test(email)) { ... }`)
- 정규식이 너무 느슨하다. 최소 `local@domain.tld` 형태를 요구하는 패턴 (예: `/^[^\s@]+@[^\s@]+\.[^\s@]+$/`) 또는 검증 라이브러리 도입이 필요하다.
