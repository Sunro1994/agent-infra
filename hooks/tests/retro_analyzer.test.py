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
