# Phase 6 — auto-retro 신호 강화 + ai_log gap 진단 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** session-end-retro 의 신호 추출을 정확하게 만들어 DRAFT confirmed 비율을 ≥1/5 로 끌어올리고, ai_log gap 의 재현 조건을 별도 보고서로 정리한다.

**Architecture:** Python 단일 모듈(`retro_analyzer.py`)이 transcript 분석 → JSON 반환, 셸은 slim wrapper. signal 함수 4개 분리 + fixture 기반 unittest. ai_log gap 은 별도 shell harness 로 환경별 재현 시도.

**Tech Stack:** Python 3 stdlib (`json`, `re`, `sys`, `os`, `unittest`), bash, Claude Code transcript jsonl.

---

## 사전 컨텍스트 (구현 전 필독)

Spec 작성 후 schema 검증에서 발견된 사실:

1. 기존 `hooks/session-end-retro.sh` 의 인라인 Python 은 `evt.get('tool_name')` / `evt.get('is_error')` 로 detection 시도했으나, 실제 Claude Code transcript jsonl 구조와 mismatch:
   - tool_use 는 `assistant.message.content[].type == "tool_use"` 에 위치하며 `.name`, `.input` 필드 사용. **top-level `tool_name` 키는 절대 없음.**
   - tool error 는 `user.message.content[].type == "tool_result"` 의 `is_error: true`. top-level `is_error` 는 거의 없음.
   - 결과적으로 기존 `duplicate_reads` / `tool_errors` detector 는 dead code 였고, `verify_keywords` (직렬화 텍스트 정규식) 만 작동해 fire 트리거 됐음. 이것이 DRAFT 8건 전수 폐기의 진짜 원인.

2. user 텍스트 turn 식별 기준:
   - `type == "user"` && `message.content` 가 **문자열** && `userType` 가 `"external"` (없으면 typed input)
   - `message.content` 가 list 인 경우는 tool_result 또는 image paste 이므로 user_correction 패턴 검사에서 제외
   - `<system-reminder>` 가 포함된 user message 는 hook injection 이므로 제외 (`'<system-reminder>' in content` 체크)

3. tool_use 식별:
   - `type == "assistant"` → `message.content` list 순회 → 항목 `.type == "tool_use"` 면 `.name`, `.input` 사용
   - 시퀀셜 인덱스는 **jsonl 라인 인덱스** (0-based)

4. session-end-retro 의 stdin 입력 포맷 (claude code SessionEnd hook contract):
   ```json
   {"session_id": "...", "transcript_path": "/abs/path.jsonl", ...}
   ```

---

## File Structure

**Create:**
- `hooks/lib/retro_analyzer.py` — signal extraction + render
- `hooks/lib/diag_session_start.sh` — ai_log gap 재현 harness
- `hooks/tests/retro_analyzer.test.py` — Python unittest
- `hooks/tests/fixtures/transcript-corrections.jsonl`
- `hooks/tests/fixtures/transcript-verify-then-change.jsonl`
- `hooks/tests/fixtures/transcript-dup-reads.jsonl`
- `hooks/tests/fixtures/transcript-clean.jsonl`
- `hooks/tests/fixtures/transcript-tool-errors.jsonl`
- `docs/reports/diagnostics/<YYYY-MM-DD>-ai-log-session-start-gap.md` (Task 11 산출물)

**Modify:**
- `hooks/session-end-retro.sh` — Python heredoc 제거 → `retro_analyzer.py` 호출 wrapper
- `hooks/tests/session-end-retro.test.sh` — 새 DRAFT 섹션 assertion 추가

---

## Task 1: 디렉토리 + Clean fixture 작성

**Files:**
- Create: `hooks/tests/fixtures/transcript-clean.jsonl`

- [ ] **Step 1: 디렉토리 생성**

```bash
mkdir -p hooks/tests/fixtures
```

- [ ] **Step 2: clean 세션 fixture 작성 (시그널 0건 예상)**

`hooks/tests/fixtures/transcript-clean.jsonl`:
```jsonl
{"type":"user","message":{"role":"user","content":"hello"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"hi there"}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":"thanks"},"userType":"external","uuid":"u2","sessionId":"s1"}
```

- [ ] **Step 3: jsonl 유효성 확인**

```bash
python3 -c "import json; [json.loads(l) for l in open('hooks/tests/fixtures/transcript-clean.jsonl')]"
```
Expected: 출력 없음 (에러 시 stderr).

- [ ] **Step 4: 커밋**

```bash
git add hooks/tests/fixtures/transcript-clean.jsonl
git commit -m "test(phase6): add clean transcript fixture"
```

---

## Task 2: retro_analyzer.py 골격 + parse_events + Clean 세션 처리

**Files:**
- Create: `hooks/lib/retro_analyzer.py`
- Create: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: 실패 테스트 작성**

`hooks/tests/retro_analyzer.test.py`:
```python
import json
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANALYZER = os.path.join(ROOT, "hooks", "lib", "retro_analyzer.py")
FIXTURES = os.path.join(ROOT, "hooks", "tests", "fixtures")


def run_analyzer(fixture_name, session_id="test-session"):
    path = os.path.join(FIXTURES, fixture_name)
    result = subprocess.run(
        ["python3", ANALYZER, path, session_id],
        capture_output=True, text=True
    )
    return result


class TestCleanSession(unittest.TestCase):
    def test_clean_session_exits_99(self):
        result = run_analyzer("transcript-clean.jsonl")
        self.assertEqual(result.returncode, 99, msg=f"stdout={result.stdout!r} stderr={result.stderr!r}")
        self.assertEqual(result.stdout.strip(), "")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: 테스트 실행 → 실패 확인**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: FAIL (analyzer 파일 없음 → returncode != 99).

- [ ] **Step 3: 최소 구현 (parse_events + clean exit)**

`hooks/lib/retro_analyzer.py`:
```python
#!/usr/bin/env python3
"""retro_analyzer — session transcript 분석 → DRAFT JSON 또는 exit 99."""

import json
import os
import re
import sys


def parse_events(transcript_path):
    events = []
    with open(transcript_path) as f:
        for line in f:
            try:
                events.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    return events


def detect_dup_reads(events):
    return []


def detect_user_corrections(events):
    return []


def detect_verify_then_change(events):
    return []


def count_tool_errors(events):
    return 0


def count_verify_keywords(events):
    return 0


def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= 3
    )


def analyze(transcript_path, session_id):
    events = parse_events(transcript_path)
    metrics = {
        "duplicate_reads": detect_dup_reads(events),
        "tool_errors": count_tool_errors(events),
        "verify_keywords": count_verify_keywords(events),
    }
    signals = detect_user_corrections(events) + detect_verify_then_change(events)
    return {
        "session_id": session_id,
        "metrics": metrics,
        "signals": signals,
    }


def render(payload):
    raise NotImplementedError("render is implemented in Task 7")


def main(argv):
    if len(argv) >= 2 and argv[1] == "--render":
        payload = json.loads(sys.stdin.read())
        sys.stdout.write(render(payload))
        return 0

    if len(argv) < 3:
        print("usage: retro_analyzer.py <transcript_path> <session_id>", file=sys.stderr)
        return 2

    transcript_path, session_id = argv[1], argv[2]
    result = analyze(transcript_path, session_id)
    if not should_fire_draft(result["metrics"], result["signals"]):
        return 99
    sys.stdout.write(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

```bash
chmod +x hooks/lib/retro_analyzer.py
```

- [ ] **Step 4: 테스트 재실행 → 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: `Ran 1 test ... OK`.

- [ ] **Step 5: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py
git commit -m "feat(phase6): scaffold retro_analyzer with clean-exit path"
```

---

## Task 3: count_tool_errors + count_verify_keywords + tool_errors fixture

**Files:**
- Create: `hooks/tests/fixtures/transcript-tool-errors.jsonl`
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: tool_errors fixture 작성 (3건 → fire)**

`hooks/tests/fixtures/transcript-tool-errors.jsonl`:
```jsonl
{"type":"user","message":{"role":"user","content":"do thing"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"false"}}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"fail","is_error":true}]},"uuid":"u2","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Bash","input":{"command":"false"}}]},"uuid":"a2","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"fail","is_error":true}]},"uuid":"u3","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Bash","input":{"command":"false"}}]},"uuid":"a3","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3","content":"fail","is_error":true}]},"uuid":"u4","sessionId":"s1"}
```

- [ ] **Step 2: 실패 테스트 추가**

`hooks/tests/retro_analyzer.test.py` 에 추가:
```python
class TestToolErrors(unittest.TestCase):
    def test_three_tool_errors_fires(self):
        result = run_analyzer("transcript-tool-errors.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        self.assertEqual(payload["metrics"]["tool_errors"], 3)

    def test_verify_keywords_counted_but_not_fired_alone(self):
        # clean fixture 에는 verify 키워드 0건, 별도 fixture 없이 unit 으로 검증
        from retro_analyzer import count_verify_keywords
        evts = [{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"verified the change"}]}}]
        self.assertEqual(count_verify_keywords(evts), 1)
```

import 경로 보강 — 파일 상단의 ROOT/ANALYZER/FIXTURES 정의 다음에 추가:
```python
sys.path.insert(0, os.path.join(ROOT, "hooks", "lib"))
```
이후 unit-level 테스트에서는 `from retro_analyzer import <func>` 형태로 import 한다 (분리된 모듈 직접 임포트, 패키지 표기 없음).

- [ ] **Step 3: 테스트 실행 → 실패**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: FAIL (tool_errors 0, verify_keywords 0).

- [ ] **Step 4: 구현**

`hooks/lib/retro_analyzer.py` 의 두 함수 교체:
```python
_VERIFY_RE = re.compile(r"\b(verified|verifying|verify)\b", re.IGNORECASE)


def count_tool_errors(events):
    n = 0
    for e in events:
        if e.get("type") != "user":
            continue
        cont = (e.get("message") or {}).get("content")
        if not isinstance(cont, list):
            continue
        for c in cont:
            if c.get("type") == "tool_result" and c.get("is_error"):
                n += 1
    return n


def count_verify_keywords(events):
    n = 0
    for e in events:
        if e.get("type") != "assistant":
            continue
        for c in (e.get("message") or {}).get("content", []) or []:
            if c.get("type") == "text":
                n += len(_VERIFY_RE.findall(c.get("text", "")))
    return n
```

- [ ] **Step 5: 테스트 통과 확인**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 3 tests pass.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py hooks/tests/fixtures/transcript-tool-errors.jsonl
git commit -m "feat(phase6): detect tool_result errors + verify keyword count"
```

---

## Task 4: detect_dup_reads + dup-reads fixture

**Files:**
- Create: `hooks/tests/fixtures/transcript-dup-reads.jsonl`
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: fixture 작성 (같은 파일 4회 Read)**

`hooks/tests/fixtures/transcript-dup-reads.jsonl`:
```jsonl
{"type":"user","message":{"role":"user","content":"read it"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"/repo/a.py"}}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"uuid":"u2","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/repo/a.py"}}]},"uuid":"a2","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t2","content":"ok"}]},"uuid":"u3","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t3","name":"Read","input":{"file_path":"/repo/a.py"}}]},"uuid":"a3","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t3","content":"ok"}]},"uuid":"u4","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t4","name":"Read","input":{"file_path":"/repo/b.py"}}]},"uuid":"a4","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t4","content":"ok"}]},"uuid":"u5","sessionId":"s1"}
```

- [ ] **Step 2: 실패 테스트 추가**

```python
class TestDupReads(unittest.TestCase):
    def test_three_reads_of_same_file_fires(self):
        result = run_analyzer("transcript-dup-reads.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        dup = payload["metrics"]["duplicate_reads"]
        self.assertEqual(len(dup), 1)
        self.assertEqual(dup[0][0], "/repo/a.py")
        self.assertEqual(dup[0][1], 3)
```

- [ ] **Step 3: 테스트 실행 → 실패**

- [ ] **Step 4: 구현**

`detect_dup_reads` 교체:
```python
def detect_dup_reads(events):
    counts = {}
    for e in events:
        if e.get("type") != "assistant":
            continue
        for c in (e.get("message") or {}).get("content", []) or []:
            if c.get("type") == "tool_use" and c.get("name") == "Read":
                path = (c.get("input") or {}).get("file_path")
                if path:
                    counts[path] = counts.get(path, 0) + 1
    return [[p, n] for p, n in counts.items() if n >= 3]
```

- [ ] **Step 5: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 4 tests pass.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py hooks/tests/fixtures/transcript-dup-reads.jsonl
git commit -m "feat(phase6): detect duplicate Read tool_use per path"
```

---

## Task 5: detect_user_corrections + corrections fixture

**Files:**
- Create: `hooks/tests/fixtures/transcript-corrections.jsonl`
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: fixture 작성**

`hooks/tests/fixtures/transcript-corrections.jsonl`:
```jsonl
{"type":"user","message":{"role":"user","content":"start"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/repo/foo.sh","old_string":"a","new_string":"b"}}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"uuid":"u2","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":"아니야 — 그게 아니라 b 가 아니라 c 였어, 되돌려"},"userType":"external","uuid":"u3","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok reverting"}]},"uuid":"a2","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":"<system-reminder>this is a hook injection — should NOT count as correction</system-reminder>"},"userType":"external","uuid":"u4","sessionId":"s1"}
```

- [ ] **Step 2: 실패 테스트 추가**

```python
class TestUserCorrections(unittest.TestCase):
    def test_one_correction_signal(self):
        result = run_analyzer("transcript-corrections.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        corrections = [s for s in payload["signals"] if s["kind"] == "user_correction"]
        self.assertEqual(len(corrections), 1)
        self.assertIn("되돌려", corrections[0]["quote"])
        self.assertEqual(corrections[0]["preceding_action"], "Edit /repo/foo.sh")

    def test_system_reminder_user_event_ignored(self):
        result = run_analyzer("transcript-corrections.jsonl")
        payload = json.loads(result.stdout)
        # 정확히 1건이어야 함 (system-reminder 포함 user 는 제외)
        corrections = [s for s in payload["signals"] if s["kind"] == "user_correction"]
        self.assertEqual(len(corrections), 1)

    def test_tool_result_user_event_ignored(self):
        from retro_analyzer import detect_user_corrections
        evts = [{"type":"user","userType":"external","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x","content":"아니야 그게 아니야"}]}}]
        self.assertEqual(detect_user_corrections(evts), [])
```

- [ ] **Step 3: 실행 → 실패**

- [ ] **Step 4: 구현**

```python
_CORRECTION_RE = re.compile(
    r"(아니야|아니라|그게\s*아니|틀렸|잘못|다시|되돌|revert|undo|stop|wait|not\s+what|wrong|incorrect|미안.*취소)",
    re.IGNORECASE,
)


def _trim_quote(text, match_start, match_end, limit=120):
    if len(text) <= limit:
        return text.strip()
    half = limit // 2
    start = max(0, match_start - half)
    end = min(len(text), match_end + half)
    snippet = text[start:end].strip()
    if start > 0:
        snippet = "…" + snippet
    if end < len(text):
        snippet = snippet + "…"
    return snippet[:limit + 2]


def _is_real_user_text(event):
    if event.get("type") != "user":
        return False
    if event.get("userType") not in (None, "external"):
        return False
    cont = (event.get("message") or {}).get("content")
    if not isinstance(cont, str):
        return False
    if "<system-reminder>" in cont:
        return False
    return True


def _summarize_assistant_action(event):
    if event.get("type") != "assistant":
        return "(none)"
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "tool_use":
            name = c.get("name", "?")
            inp = c.get("input") or {}
            arg = inp.get("file_path") or inp.get("command") or inp.get("pattern") or ""
            arg = str(arg).splitlines()[0][:60]
            return f"{name} {arg}".strip()
    return "(text only)"


def detect_user_corrections(events):
    signals = []
    for idx, e in enumerate(events):
        if not _is_real_user_text(e):
            continue
        text = e["message"]["content"]
        m = _CORRECTION_RE.search(text)
        if not m:
            continue
        # 직전 assistant event 찾기
        preceding = "(none)"
        for j in range(idx - 1, -1, -1):
            if events[j].get("type") == "assistant":
                preceding = _summarize_assistant_action(events[j])
                break
        signals.append({
            "kind": "user_correction",
            "turn_index": idx,
            "quote": _trim_quote(text, m.start(), m.end()),
            "preceding_action": preceding,
        })
    return signals
```

- [ ] **Step 5: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 7 tests pass.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py hooks/tests/fixtures/transcript-corrections.jsonl
git commit -m "feat(phase6): detect user correction turns with evidence quote"
```

---

## Task 6: detect_verify_then_change + fixture

**Files:**
- Create: `hooks/tests/fixtures/transcript-verify-then-change.jsonl`
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: fixture 작성**

`hooks/tests/fixtures/transcript-verify-then-change.jsonl`:
```jsonl
{"type":"user","message":{"role":"user","content":"do it"},"userType":"external","uuid":"u1","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t1","name":"Edit","input":{"file_path":"/repo/x.sh","old_string":"a","new_string":"b"}}]},"uuid":"a1","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]},"uuid":"u2","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Verified the fix works now."}]},"uuid":"a2","sessionId":"s1"}
{"type":"user","message":{"role":"user","content":"good"},"userType":"external","uuid":"u3","sessionId":"s1"}
{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"t2","name":"Edit","input":{"file_path":"/repo/x.sh","old_string":"b","new_string":"c"}}]},"uuid":"a3","sessionId":"s1"}
```

- [ ] **Step 2: 실패 테스트 추가**

```python
class TestVerifyThenChange(unittest.TestCase):
    def test_signal_fires(self):
        result = run_analyzer("transcript-verify-then-change.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        vtc = [s for s in payload["signals"] if s["kind"] == "verify_then_change"]
        self.assertEqual(len(vtc), 1)
        self.assertEqual(vtc[0]["file"], "/repo/x.sh")
        self.assertIn("Verified", vtc[0]["verify_quote"])

    def test_no_signal_when_change_too_far(self):
        from retro_analyzer import detect_verify_then_change
        evts = [
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"verified"}]}},
            {"type":"user","message":{"role":"user","content":"a"},"userType":"external"},
            {"type":"user","message":{"role":"user","content":"b"},"userType":"external"},
            {"type":"user","message":{"role":"user","content":"c"},"userType":"external"},
            {"type":"user","message":{"role":"user","content":"d"},"userType":"external"},
            {"type":"user","message":{"role":"user","content":"e"},"userType":"external"},
            {"type":"user","message":{"role":"user","content":"f"},"userType":"external"},
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/x"}}]}},
        ]
        # verify_turn=0, change_turn=7 → 7 events apart > 5
        self.assertEqual(detect_verify_then_change(evts), [])

    def test_no_signal_when_change_is_different_file(self):
        from retro_analyzer import detect_verify_then_change
        evts = [
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/a"}}]}},
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"verified"}]}},
            {"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","name":"Edit","input":{"file_path":"/b"}}]}},
        ]
        self.assertEqual(detect_verify_then_change(evts), [])
```

- [ ] **Step 3: 실행 → 실패**

- [ ] **Step 4: 구현**

설계 노트: spec §4(b) 는 "verify 이후 ≤5 events 내 동일 파일 Edit/Write" 로 정의하지만, "동일 파일" 의 시맨틱을 strict 하게 적용 — verify 시점 이전에 동일 세션에서 한 번이라도 편집됐던 파일에 한정한다. 신규 파일에 대한 verify→edit 는 verify 가 그 파일을 가리킬 수 없으므로 false-positive 감소 목적.

```python
_VERIFY_TRIGGER_RE = re.compile(
    r"\b(verified|passing\s*now|passes\s*now|fixed|complete|works\s*now|confirmed)\b",
    re.IGNORECASE,
)


def _assistant_text(event):
    parts = []
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "text":
            parts.append(c.get("text", ""))
    return "\n".join(parts)


def _files_edited_by(event):
    out = []
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "tool_use" and c.get("name") in ("Edit", "Write"):
            path = (c.get("input") or {}).get("file_path")
            if path:
                out.append((path, c.get("name")))
    return out


def detect_verify_then_change(events):
    signals = []
    seen_pairs = set()
    for vi, e in enumerate(events):
        if e.get("type") != "assistant":
            continue
        text = _assistant_text(e)
        m = _VERIFY_TRIGGER_RE.search(text)
        if not m:
            continue
        # 같은 turn 이전에 등장한 파일(verify-스코프) 추출
        prior_files = set()
        for j in range(vi):
            ej = events[j]
            if ej.get("type") == "assistant":
                for path, _ in _files_edited_by(ej):
                    prior_files.add(os.path.realpath(path) if os.path.isabs(path) else path)
        for ci in range(vi + 1, min(len(events), vi + 6)):
            ec = events[ci]
            if ec.get("type") != "assistant":
                continue
            for path, name in _files_edited_by(ec):
                norm = os.path.realpath(path) if os.path.isabs(path) else path
                if norm not in prior_files:
                    continue
                key = (vi, ci, norm)
                if key in seen_pairs:
                    continue
                seen_pairs.add(key)
                signals.append({
                    "kind": "verify_then_change",
                    "file": norm,
                    "verify_turn": vi,
                    "change_turn": ci,
                    "verify_quote": _trim_quote(text, m.start(), m.end()),
                    "change_quote": f"{name} {path}",
                })
                break
    return signals
```

- [ ] **Step 5: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 10 tests pass.

- [ ] **Step 6: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py hooks/tests/fixtures/transcript-verify-then-change.jsonl
git commit -m "feat(phase6): detect verify-then-change pattern per file"
```

---

## Task 7: --render mode (JSON → DRAFT markdown)

**Files:**
- Modify: `hooks/lib/retro_analyzer.py`
- Modify: `hooks/tests/retro_analyzer.test.py`

- [ ] **Step 1: 실패 테스트 추가**

```python
class TestRender(unittest.TestCase):
    def test_render_outputs_frontmatter_and_signal_sections(self):
        payload = {
            "session_id": "abc",
            "metrics": {"duplicate_reads": [["/repo/a.py", 4]], "tool_errors": 1, "verify_keywords": 7},
            "signals": [
                {"kind": "user_correction", "turn_index": 3, "quote": "되돌려", "preceding_action": "Edit /repo/foo.sh"},
                {"kind": "verify_then_change", "file": "/repo/foo.sh", "verify_turn": 5, "change_turn": 7,
                 "verify_quote": "Verified the fix", "change_quote": "Edit /repo/foo.sh"},
            ],
        }
        proc = subprocess.run(
            ["python3", ANALYZER, "--render"],
            input=json.dumps(payload), capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 0, msg=f"stderr={proc.stderr!r}")
        out = proc.stdout
        self.assertIn("name: feedback-retro-", out)
        self.assertIn("signal_count: 2", out)
        self.assertIn("session_id: abc", out)
        self.assertIn("## 🚨 사용자 정정", out)
        self.assertIn("## ⚠️ verify→change", out)
        self.assertIn("turn 3", out)
        self.assertIn("Edit /repo/foo.sh", out)

    def test_render_skips_empty_sections(self):
        payload = {
            "session_id": "abc",
            "metrics": {"duplicate_reads": [], "tool_errors": 5, "verify_keywords": 0},
            "signals": [],
        }
        proc = subprocess.run(
            ["python3", ANALYZER, "--render"],
            input=json.dumps(payload), capture_output=True, text=True,
        )
        self.assertNotIn("## 🚨", proc.stdout)
        self.assertNotIn("## ⚠️", proc.stdout)
        self.assertIn("tool_errors=5", proc.stdout)
```

- [ ] **Step 2: 실행 → 실패** (NotImplementedError 발생)

- [ ] **Step 3: render 구현**

`retro_analyzer.py` 의 `render` 교체:
```python
import datetime


def _now_slug():
    # SLUG 은 셸이 결정해서 넘기지만, render 자체는 timestamp 도 자체 생성 가능하게 둠
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S")


def render(payload):
    session_id = payload["session_id"]
    metrics = payload["metrics"]
    signals = payload.get("signals", [])
    slug = _now_slug()

    lines = []
    lines.append("---")
    lines.append(f"name: feedback-retro-{slug}")
    lines.append('description: "세션 자동 회고 초안 — 사용자 검토 후 확정/폐기"')
    lines.append("metadata:")
    lines.append("  type: feedback")
    lines.append("  status: draft")
    lines.append(f"  session_id: {session_id}")
    lines.append(f"  signal_count: {len(signals)}")
    lines.append("---")
    lines.append("")
    lines.append("# 자동 회고 초안")
    lines.append("")
    lines.append(f"session: {session_id}")
    dup = metrics.get("duplicate_reads", [])
    lines.append(
        "metrics: duplicate_reads="
        + repr(dup)
        + f" tool_errors={metrics.get('tool_errors', 0)}"
        + f" verify_keywords={metrics.get('verify_keywords', 0)}"
    )
    lines.append("")

    corrections = [s for s in signals if s["kind"] == "user_correction"]
    vtc = [s for s in signals if s["kind"] == "verify_then_change"]

    if corrections:
        lines.append(f"## 🚨 사용자 정정 ({len(corrections)}건)")
        for s in corrections:
            lines.append(f"**turn {s['turn_index']}** — `assistant: {s['preceding_action']}` 직후")
            lines.append(f"> \"{s['quote']}\"")
            lines.append("")

    if vtc:
        lines.append(f"## ⚠️ verify→change ({len(vtc)}건)")
        for s in vtc:
            lines.append(f"**turn {s['verify_turn']}→{s['change_turn']}** `{s['file']}`")
            lines.append(f"- verify: \"{s['verify_quote']}\"")
            lines.append(f"- change: {s['change_quote']}")
            lines.append("")

    lines.append("**다음 액션**:")
    lines.append("- 확정 시: -DRAFT 제거 + 본문을 feedback memory body 구조(rule + **Why:** + **How to apply:**)로 재작성 + MEMORY.md 인덱스 추가")
    lines.append("- 폐기 시: 파일 삭제")
    lines.append("")
    return "\n".join(lines)
```

- [ ] **Step 4: 테스트 통과**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 12 tests pass.

- [ ] **Step 5: 커밋**

```bash
git add hooks/lib/retro_analyzer.py hooks/tests/retro_analyzer.test.py
git commit -m "feat(phase6): render DRAFT markdown from analyzer JSON"
```

---

## Task 8: session-end-retro.sh 전환 + 기존 e2e 테스트 갱신

**Files:**
- Modify: `hooks/session-end-retro.sh`
- Modify: `hooks/tests/session-end-retro.test.sh`

- [ ] **Step 1: 기존 e2e 테스트 확인**

```bash
cat hooks/tests/session-end-retro.test.sh
```
구조 파악만. 다음 step 에서 assertion 추가.

- [ ] **Step 2: e2e 테스트에 새 fixture 기반 assertion 추가**

`hooks/tests/session-end-retro.test.sh` 에 새 케이스 추가 (기존 테스트 보존):
```bash
# Test: corrections fixture → DRAFT 생성 + 새 섹션 포함
TMPDIR=$(mktemp -d)
TRANSCRIPT="$TMPDIR/transcript.jsonl"
cp "$(dirname "$0")/fixtures/transcript-corrections.jsonl" "$TRANSCRIPT"
INPUT_JSON="{\"session_id\":\"e2e-corr\",\"transcript_path\":\"$TRANSCRIPT\"}"

echo "$INPUT_JSON" | bash "$(dirname "$0")/../session-end-retro.sh"

DRAFT=$(ls "$TMPDIR"/memory/feedback-retro-*-DRAFT.md 2>/dev/null | head -1)
[ -z "$DRAFT" ] && { echo "FAIL: no DRAFT created for corrections fixture"; exit 1; }
grep -q "## 🚨 사용자 정정" "$DRAFT" || { echo "FAIL: corrections section missing"; exit 1; }
echo "PASS: corrections e2e"
rm -rf "$TMPDIR"

# Test: clean fixture → DRAFT 생성 안 됨
TMPDIR=$(mktemp -d)
TRANSCRIPT="$TMPDIR/transcript.jsonl"
cp "$(dirname "$0")/fixtures/transcript-clean.jsonl" "$TRANSCRIPT"
INPUT_JSON="{\"session_id\":\"e2e-clean\",\"transcript_path\":\"$TRANSCRIPT\"}"

echo "$INPUT_JSON" | bash "$(dirname "$0")/../session-end-retro.sh"

if ls "$TMPDIR"/memory/feedback-retro-*-DRAFT.md 2>/dev/null | head -1 >/dev/null; then
  echo "FAIL: DRAFT created for clean fixture"
  exit 1
fi
echo "PASS: clean e2e (no DRAFT)"
rm -rf "$TMPDIR"
```

주의: `session-end-retro.sh` 가 `transcript_path` 의 dirname 에 `memory/` 를 만들기 때문에 위 fixture 흐름이 그대로 작동한다 (`PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")`).

- [ ] **Step 3: e2e 테스트 실행 → 실패 (아직 wrapper 미전환)**

```bash
bash hooks/tests/session-end-retro.test.sh
```
Expected: FAIL on corrections (구버전 detector 가 신호 못 잡음).

- [ ] **Step 4: session-end-retro.sh 전환**

`hooks/session-end-retro.sh` 의 `PY_SCRIPT` heredoc 블록과 `python3 -c` 호출 부분 제거, 다음으로 교체:

```sh
#!/usr/bin/env bash
# session-end-retro.sh — 세션 종료 시 transcript 분석 → feedback 메모리 초안

set +e
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

ANALYSIS_JSON=$(python3 "$INFRA_DIR/lib/retro_analyzer.py" "$TRANSCRIPT_PATH" "$SESSION_ID" 2>>"$AI_LOG_FILE")
EXIT_CODE=$?

case "$EXIT_CODE" in
    99) ai_log "no significant patterns, skipping draft"; exit 0 ;;
    0)  ;;
    *)  ai_log "analyzer failed exit=$EXIT_CODE"; exit 0 ;;
esac

SLUG=$(date +"%Y%m%d-%H%M%S")
DRAFT_FILE="$MEMORY_DIR/feedback-retro-$SLUG-DRAFT.md"
printf '%s' "$ANALYSIS_JSON" | python3 "$INFRA_DIR/lib/retro_analyzer.py" --render > "$DRAFT_FILE"

ai_log "draft created: $DRAFT_FILE"
exit 0
```

- [ ] **Step 5: e2e 테스트 통과**

```bash
bash hooks/tests/session-end-retro.test.sh
```
Expected: 모든 케이스 PASS.

- [ ] **Step 6: 단위테스트도 회귀 확인**

```bash
python3 hooks/tests/retro_analyzer.test.py
```
Expected: 12 tests pass.

- [ ] **Step 7: 커밋**

```bash
git add hooks/session-end-retro.sh hooks/tests/session-end-retro.test.sh
git commit -m "feat(phase6): swap session-end-retro inline Python for retro_analyzer.py"
```

---

## Task 9: 실제 transcript 스모크 + 잔존 DRAFT 정리 안내

**Files:** 검증만, 변경 없음 (지표 기록은 별도 보고)

- [ ] **Step 1: 최근 transcript 5개에 대해 analyzer 수동 실행**

```bash
for f in $(ls -t /Users/leeseonro/.claude/projects/-Users-leeseonro-agent-infra/*.jsonl | head -5); do
  echo "=== $f ==="
  python3 hooks/lib/retro_analyzer.py "$f" "smoke" 2>/dev/null | python3 -m json.tool 2>/dev/null || echo "(no signal — exit 99)"
done
```

확인 항목:
- exit 99 (clean) 와 fire (시그널 있음) 가 모두 나오는지
- 시그널이 fire 됐다면 quote 가 의미있는 텍스트인지

- [ ] **Step 2: 결과를 docs/reports/diagnostics 디렉토리에 메모**

```bash
mkdir -p docs/reports/diagnostics
```

`docs/reports/diagnostics/$(date +%Y-%m-%d)-phase6-smoke.md` 파일 신규 작성. 5개 transcript 별 (a) exit code, (b) signal count, (c) 1줄 평가 기록.

- [ ] **Step 3: 잔존 DRAFT 2건 사용자 안내**

`feedback-retro-20260611-020753-DRAFT.md`, `feedback-retro-20260611-020817-DRAFT.md` 는 Phase 6 가 직접 처리하지 않음. 스모크 결과 문서 끝에 "사용자 처리 필요" 명시.

- [ ] **Step 4: 커밋**

```bash
git add docs/reports/diagnostics/*.md
git commit -m "docs(phase6): record analyzer smoke results on recent transcripts"
```

---

## Task 10: diag_session_start.sh 구현

**Files:**
- Create: `hooks/lib/diag_session_start.sh`

- [ ] **Step 1: harness 스크립트 작성**

`hooks/lib/diag_session_start.sh`:
```bash
#!/usr/bin/env bash
# diag_session_start.sh — ai_log gap 재현 harness
# 사용: bash hooks/lib/diag_session_start.sh

set -u

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
HOOK="$INFRA_DIR/session-start-retro-alert.sh"
TMPLOG=$(mktemp)
SAMPLE_INPUT='{"cwd":"'"$INFRA_DIR"'"}'

run_env() {
    local label="$1"; shift
    echo "===== ENV: $label ====="

    local resolved
    resolved=$("$@" bash -c 'echo "$HOME"::"${AI_LOG_FILE:-$HOME/.claude/hooks/.log}"')
    echo "resolved: $resolved"

    local logfile="${HOME}/.claude/hooks/.log"
    local lines_before=0
    [ -f "$logfile" ] && lines_before=$(wc -l < "$logfile" | tr -d ' ')

    local stdout_capture stderr_capture exit_code
    set +e
    stdout_capture=$(printf '%s' "$SAMPLE_INPUT" | "$@" bash "$HOOK" 2>"$TMPLOG")
    exit_code=$?
    stderr_capture=$(cat "$TMPLOG")
    set -e

    local lines_after=0
    [ -f "$logfile" ] && lines_after=$(wc -l < "$logfile" | tr -d ' ')

    echo "exit: $exit_code"
    echo "stdout(${#stdout_capture}b): $stdout_capture" | head -c 300
    echo
    echo "stderr: $stderr_capture" | head -c 300
    echo
    echo "ai_log delta: $((lines_after - lines_before))"
    echo
}

run_env "normal" env
run_env "stripped" env -i HOME="$HOME" PATH="$PATH"
run_env "no_home" env -i PATH="$PATH"

rm -f "$TMPLOG"
```

```bash
chmod +x hooks/lib/diag_session_start.sh
```

- [ ] **Step 2: harness 실행 (수동)**

```bash
bash hooks/lib/diag_session_start.sh
```

3개 환경의 출력 캡처 (terminal scrollback 또는 redirect).

- [ ] **Step 3: 커밋**

```bash
git add hooks/lib/diag_session_start.sh
git commit -m "feat(phase6): add diag_session_start harness for ai_log gap repro"
```

---

## Task 11: ai_log gap 진단 보고서 작성

**Files:**
- Create: `docs/reports/diagnostics/<YYYY-MM-DD>-ai-log-session-start-gap.md`

- [ ] **Step 1: 보고서 골격 작성**

오늘 날짜로 `docs/reports/diagnostics/2026-06-11-ai-log-session-start-gap.md` (실제 작성 일자에 맞게):

```markdown
# ai_log gap (SessionStart:startup) 진단 보고서

작성일: <YYYY-MM-DD>
관련 사이클: Phase 6 (auto-retro 신호 강화와 묶음 진행)
범위: **재현 조건 규명만**. 수정은 별도 사이클.

## 배경

Phase 5 종료 직후 발견: 일부 SessionStart:startup 실행이 transcript attachment 에는 hook 실행 기록을 남기지만 `~/.claude/hooks/.log` 엔 해당 entry 가 누락. surface(stdout) 자체는 정상 동작.

## 재현 harness

`hooks/lib/diag_session_start.sh` 가 3개 환경에서 `session-start-retro-alert.sh` 를 호출 후 (a) `$HOME` resolved, (b) `AI_LOG_FILE` resolved, (c) ai_log delta (라인 수 차) 를 캡처.

### 환경별 결과 (Task 10 실행 결과 채우기)

| Env | $HOME | AI_LOG_FILE | exit | stdout 발생 | ai_log delta |
|---|---|---|---|---|---|
| normal | <기록> | <기록> | <기록> | <기록> | <기록> |
| stripped | <기록> | <기록> | <기록> | <기록> | <기록> |
| no_home | <기록> | <기록> | <기록> | <기록> | <기록> |

## 가설 검증

1. **$HOME unset → AI_LOG_FILE 권한 실패**
   - 검증 결과: <yes/no/unverified>
   - 근거: <환경별 delta 비교>

2. **mkdir -p silent fail 후 append redirect 도 silent**
   - 검증 결과: <yes/no/unverified>
   - 근거: <stderr 확인>

3. **launcher 가 AI_LOG_FILE 을 다른 경로로 override**
   - 검증 결과: <yes/no/unverified>
   - 근거: <SessionStart:startup 실제 env 캡처가 있다면 비교>

4. **stdout/stderr 라우팅 차이로 ai_log() append 실패가 invisible**
   - 검증 결과: <yes/no/unverified>
   - 근거: <strace 또는 직접 호출>

## 추정 root cause

<결론>

## 후속 사이클 작업 제안

- <fix 방향>
- <테스트 보강 제안>
```

- [ ] **Step 2: Task 10 harness 결과로 표 채우기**

`bash hooks/lib/diag_session_start.sh > /tmp/diag.out 2>&1` 후 표 채움. observed (실제 SessionStart:startup env) 캡처는 시간 제약 상 unverified 로 남겨도 무방 — Phase 6 종료 후 별도 cycle 에서 wrapper 부착 → 추후 보강.

- [ ] **Step 3: 가설 4개에 yes/no/unverified 모두 명시**

성공 기준: 4개 모두 빈칸 없이 채워져야 함.

- [ ] **Step 4: 커밋**

```bash
git add docs/reports/diagnostics/*-ai-log-session-start-gap.md
git commit -m "docs(phase6): ai_log gap diagnostic report — repro conditions"
```

---

## Verification Checklist

Phase 6 종료 시 모두 PASS:

- [ ] `python3 hooks/tests/retro_analyzer.test.py` 12개 통과
- [ ] `bash hooks/tests/session-end-retro.test.sh` 모든 케이스 통과
- [ ] Task 9 스모크 보고서 존재 + 최근 5개 transcript 결과 기록
- [ ] Task 11 진단 보고서 존재 + 4개 가설 모두 판정 완료
- [ ] 잔존 DRAFT 2건 처리 안내 문서화

## Out of Scope (Phase 7 후보)

- ai_log gap 의 root cause **fix**
- DRAFT auto-confirm
- 크로스-세션 패턴 집계
- 다국어 패턴 튜닝
