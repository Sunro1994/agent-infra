#!/usr/bin/env python3
"""retro_analyzer — session transcript 분석 → DRAFT JSON 또는 exit 99."""

import datetime
import json
import os
import re
import sys

_TOOL_ERRORS_THRESHOLD = int(os.environ.get("AI_RETRO_MIN_TOOL_ERRORS", "3"))
_DUP_READ_THRESHOLD = int(os.environ.get("AI_RETRO_DUP_READ_THRESHOLD", "3"))

_VERIFY_RE = re.compile(r"\b(verified|verifying|verify)\b", re.IGNORECASE)


def _now_slug():
    return datetime.datetime.now().strftime("%Y%m%d-%H%M%S")

_CORRECTION_RE = re.compile(
    r"(아니야|아니라|그게\s*아니|틀렸|잘못|다시|되돌|revert|undo|stop|wait|not\s+what|wrong|incorrect|미안.*취소)",
    re.IGNORECASE,
)


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
    counts = {}
    for e in events:
        if e.get("type") != "assistant":
            continue
        for c in (e.get("message") or {}).get("content", []) or []:
            if c.get("type") == "tool_use" and c.get("name") == "Read":
                path = (c.get("input") or {}).get("file_path")
                if path:
                    counts[path] = counts.get(path, 0) + 1
    return [[p, n] for p, n in counts.items() if n >= _DUP_READ_THRESHOLD]


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
    text_parts = []
    for c in (event.get("message") or {}).get("content", []) or []:
        if c.get("type") == "tool_use":
            name = c.get("name", "?")
            inp = c.get("input") or {}
            arg = inp.get("file_path") or inp.get("command") or inp.get("pattern") or ""
            arg = str(arg).splitlines()[0][:60]
            return f"{name} {arg}".strip()
        elif c.get("type") == "text":
            text_parts.append(c.get("text", ""))
    if text_parts:
        joined = " ".join(text_parts).strip()
        snippet = joined.splitlines()[0][:60] if joined else ""
        if snippet:
            return f"(text) {snippet}"
        return "(text only)"
    return "(none)"


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


def should_fire_draft(metrics, signals):
    return (
        bool(signals)
        or len(metrics["duplicate_reads"]) > 0
        or metrics["tool_errors"] >= _TOOL_ERRORS_THRESHOLD
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
