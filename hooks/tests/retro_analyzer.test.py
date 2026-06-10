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


if __name__ == "__main__":
    unittest.main()
