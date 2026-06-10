#!/usr/bin/env python3
"""retro_analyzer — session transcript 분석 → DRAFT JSON 또는 exit 99."""

import json
import os
import re
import sys


_VERIFY_RE = re.compile(r"\b(verified|verifying|verify)\b", re.IGNORECASE)


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
