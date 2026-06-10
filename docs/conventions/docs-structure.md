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
