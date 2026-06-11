import json
import os
import subprocess
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ANALYZER = os.path.join(ROOT, "hooks", "lib", "retro_analyzer.py")
FIXTURES = os.path.join(ROOT, "hooks", "tests", "fixtures")
sys.path.insert(0, os.path.join(ROOT, "hooks", "lib"))


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


class TestDupReads(unittest.TestCase):
    def test_three_reads_of_same_file_fires(self):
        result = run_analyzer("transcript-dup-reads.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        dup = payload["metrics"]["duplicate_reads"]
        self.assertEqual(len(dup), 1)
        self.assertEqual(dup[0][0], "/repo/a.py")
        self.assertEqual(dup[0][1], 3)


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


class TestThresholdEnvVar(unittest.TestCase):
    def test_higher_tool_errors_threshold_skips_fire(self):
        path = os.path.join(FIXTURES, "transcript-tool-errors.jsonl")
        env = {**os.environ, "AI_RETRO_MIN_TOOL_ERRORS": "5"}
        proc = subprocess.run(
            ["python3", ANALYZER, path, "thr-high"],
            env=env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 99, msg=f"stdout={proc.stdout!r}")

    def test_higher_dup_reads_threshold_skips_fire(self):
        path = os.path.join(FIXTURES, "transcript-dup-reads.jsonl")
        env = {**os.environ, "AI_RETRO_DUP_READ_THRESHOLD": "5"}
        proc = subprocess.run(
            ["python3", ANALYZER, path, "thr-dup"],
            env=env, capture_output=True, text=True,
        )
        self.assertEqual(proc.returncode, 99, msg=f"stdout={proc.stdout!r}")


class TestTextOnlyPreceding(unittest.TestCase):
    def test_text_only_preceding_includes_snippet(self):
        result = run_analyzer("transcript-text-preceding.jsonl")
        self.assertEqual(result.returncode, 0, msg=f"stderr={result.stderr!r}")
        payload = json.loads(result.stdout)
        corrections = [s for s in payload["signals"] if s["kind"] == "user_correction"]
        self.assertEqual(len(corrections), 1)
        prec = corrections[0]["preceding_action"]
        self.assertTrue(prec.startswith("(text) "), msg=f"got {prec!r}")
        self.assertIn("검증을 끝낸", prec)

    def test_empty_text_falls_back_to_text_only(self):
        from retro_analyzer import _summarize_assistant_action
        evt = {"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":""}]}}
        self.assertEqual(_summarize_assistant_action(evt), "(text only)")


if __name__ == "__main__":
    unittest.main()
