"""Unit tests for tools/veo_backdrops.py (stdlib unittest; urllib is mocked, no network).

Run from the repo root:
    python3 -m unittest tools.test_veo_backdrops
    python3 -m unittest tools/test_veo_backdrops.py
"""

from __future__ import annotations

import io
import json
import os
import sys
import tempfile
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import veo_backdrops  # noqa: E402

PROMPTS = [
    {"name": "clip_a", "prompt": "bone cathedral, teal mist, static camera"},
    {"name": "clip_b", "prompt": "dragon skull crypt, slow fog"},
]


class _FakeResponse(io.BytesIO):
    """Minimal context-manager stand-in for the object urlopen returns."""

    def __enter__(self):
        return self

    def __exit__(self, *_exc):
        self.close()
        return False


def _urlopen_script(*bodies: bytes):
    """Return a fake urlopen that answers successive calls with `bodies` and records requests."""
    calls: list = []
    responses = iter(bodies)

    def fake_urlopen(request, timeout=None):
        calls.append(request)
        return _FakeResponse(next(responses))

    fake_urlopen.calls = calls
    return fake_urlopen


class VeoBackdropsTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)
        self.prompt_file = self.root / "prompts.json"
        self.prompt_file.write_text(json.dumps(PROMPTS), encoding="utf-8")
        self.ledger = self.root / "spend.json"
        self.out = self.root / "raw"
        self._env = mock.patch.dict(os.environ, {"GEMINI_API_KEY": "sk-test-SECRET"})
        self._env.start()

    def tearDown(self) -> None:
        self._env.stop()
        self._tmp.cleanup()

    def _run(self, *extra: str) -> tuple[int, str, str]:
        argv = [
            "--prompt-file", str(self.prompt_file),
            "--out", str(self.out),
            "--ledger", str(self.ledger),
            *extra,
        ]
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = veo_backdrops.main(argv)
        return code, out.getvalue(), err.getvalue()

    # ------------------------------------------------------------------ budget

    def test_budget_refusal_sends_nothing_and_leaves_ledger_untouched(self) -> None:
        # 8 s * $0.15 = $1.20; with $27.00 already spent the clip would reach $28.20 > $28.00.
        before = {"spent_usd": 27.0, "clips": [{"name": "old", "cost_usd": 27.0}]}
        self.ledger.write_text(json.dumps(before), encoding="utf-8")
        fake = _urlopen_script()
        with mock.patch("urllib.request.urlopen", fake), mock.patch("time.sleep"):
            code, _out, err = self._run("--budget-usd", "28")
        self.assertEqual(code, veo_backdrops.EXIT_BUDGET)
        self.assertEqual(fake.calls, [], "no HTTP request may be made for a refused clip")
        self.assertIn("exceeds budget $28.00", err)
        self.assertEqual(json.loads(self.ledger.read_text(encoding="utf-8")), before)
        self.assertFalse(self.out.exists())

    def test_budget_allows_exactly_reaching_the_limit(self) -> None:
        ledger = {"spent_usd": 26.8, "clips": []}
        entry = {"name": "x", "cost_usd": 1.2}
        veo_backdrops.reserve_spend(ledger, entry, 28.0)  # 26.8 + 1.2 == 28.0: allowed
        self.assertEqual(ledger["spent_usd"], 28.0)
        with self.assertRaises(veo_backdrops.BudgetExceeded):
            veo_backdrops.reserve_spend(ledger, {"name": "y", "cost_usd": 0.01}, 28.0)

    def test_price_table_and_override(self) -> None:
        table = [
            ("veo-3.1-fast-generate-preview", 0.15),
            ("veo-3.1-generate-preview", 0.40),
            ("veo-3.0-fast-generate-001", 0.15),
        ]
        for model, want in table:
            self.assertEqual(veo_backdrops.price_for_model(model), want, model)
        self.assertEqual(veo_backdrops.estimate_cost(8, 0.15), 1.2)
        self.assertEqual(veo_backdrops.estimate_cost(8, 0.40), 3.2)

    # ------------------------------------------------------------------ ledger + download

    def test_successful_clip_updates_ledger_and_writes_mp4(self) -> None:
        fake = _urlopen_script(
            json.dumps({"name": "models/veo/operations/op-1"}).encode(),
            json.dumps({"name": "models/veo/operations/op-1", "done": False}).encode(),
            json.dumps(
                {
                    "name": "models/veo/operations/op-1",
                    "done": True,
                    "response": {
                        "generateVideoResponse": {
                            "generatedSamples": [
                                {"video": {"uri": "https://generativelanguage.googleapis.com/v1beta/files/f1:download?alt=media"}}
                            ]
                        }
                    },
                }
            ).encode(),
            b"\x00\x00\x00\x18ftypmp42fake-video-bytes",
        )
        with mock.patch("urllib.request.urlopen", fake), mock.patch("time.sleep") as sleep:
            code, out, err = self._run("--max-clips", "1")
        self.assertEqual(code, veo_backdrops.EXIT_OK, err)
        self.assertEqual(len(fake.calls), 4, "POST, poll (not done), poll (done), download")
        sleep.assert_called_once_with(veo_backdrops.POLL_SECONDS)
        self.assertEqual(fake.calls[1].full_url, "https://generativelanguage.googleapis.com/v1beta/models/veo/operations/op-1")
        self.assertEqual(fake.calls[1].get_method(), "GET")
        self.assertEqual(fake.calls[3].get_header("X-goog-api-key"), "sk-test-SECRET")
        self.assertNotIn("key=", fake.calls[3].full_url, "key travels in the header, not the URL")

        clip = self.out / "clip_a.mp4"
        self.assertEqual(clip.read_bytes(), b"\x00\x00\x00\x18ftypmp42fake-video-bytes")
        ledger = json.loads(self.ledger.read_text(encoding="utf-8"))
        self.assertEqual(ledger["spent_usd"], 1.2)
        self.assertEqual(len(ledger["clips"]), 1)
        entry = ledger["clips"][0]
        self.assertEqual(entry["name"], "clip_a")
        self.assertEqual(entry["cost_usd"], 1.2)
        self.assertEqual(entry["status"], "done")
        self.assertEqual(entry["operation"], "models/veo/operations/op-1")
        self.assertNotIn("sk-test-SECRET", out + err + self.ledger.read_text(encoding="utf-8"))

    def test_spend_is_reserved_before_the_request_and_kept_on_failure(self) -> None:
        fake = _urlopen_script(
            json.dumps({"name": "models/veo/operations/op-2"}).encode(),
            json.dumps({"name": "models/veo/operations/op-2", "done": True, "error": {"code": 13, "message": "boom"}}).encode(),
        )
        with mock.patch("urllib.request.urlopen", fake), mock.patch("time.sleep"):
            code, _out, err = self._run("--max-clips", "1")
        self.assertEqual(code, veo_backdrops.EXIT_ERROR)
        self.assertIn("boom", err)
        ledger = json.loads(self.ledger.read_text(encoding="utf-8"))
        self.assertEqual(ledger["spent_usd"], 1.2, "a failed clip still counts against the budget")
        self.assertEqual(ledger["clips"][0]["status"], "failed")

    def test_network_failure_is_recorded_as_failed_without_a_traceback(self) -> None:
        # URLError is not a RuntimeError: without the broad except, main() would raise instead of
        # returning EXIT_ERROR and the ledger entry would stay "started" with no error recorded.
        def refuse(_request, timeout=None):
            raise urllib.error.URLError("proxy refused")

        with mock.patch("urllib.request.urlopen", refuse), mock.patch("time.sleep"):
            code, _out, err = self._run("--max-clips", "1")
        self.assertEqual(code, veo_backdrops.EXIT_ERROR)
        self.assertIn("proxy refused", err)
        ledger = json.loads(self.ledger.read_text(encoding="utf-8"))
        self.assertEqual(ledger["spent_usd"], 1.2, "the reservation still counts")
        self.assertEqual(ledger["clips"][0]["status"], "failed")
        self.assertIn("proxy refused", ledger["clips"][0]["error"])

    def test_existing_clip_is_skipped_and_not_billed_again(self) -> None:
        self.out.mkdir()
        (self.out / "clip_a.mp4").write_bytes(b"already here")
        fake = _urlopen_script(
            json.dumps({"name": "models/veo/operations/op-9"}).encode(),
            json.dumps(
                {
                    "name": "models/veo/operations/op-9",
                    "done": True,
                    "response": {"generateVideoResponse": {"generatedSamples": [{"video": {"uri": "https://x/v"}}]}},
                }
            ).encode(),
            b"clip-b-bytes",
        )
        with mock.patch("urllib.request.urlopen", fake), mock.patch("time.sleep"):
            code, out, err = self._run()
        self.assertEqual(code, veo_backdrops.EXIT_OK, err)
        self.assertIn("clip_a.mp4 exists, skipping", out)
        self.assertEqual(len(fake.calls), 3, "only clip_b hits the network: POST, poll, download")
        self.assertEqual((self.out / "clip_a.mp4").read_bytes(), b"already here")
        ledger = json.loads(self.ledger.read_text(encoding="utf-8"))
        self.assertEqual(ledger["spent_usd"], 1.2, "only clip_b is billed")
        self.assertEqual([c["name"] for c in ledger["clips"]], ["clip_b"])

    def test_missing_api_key_is_an_error_before_any_request(self) -> None:
        fake = _urlopen_script()
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch("urllib.request.urlopen", fake):
            code, _out, err = self._run()
        self.assertEqual(code, veo_backdrops.EXIT_ERROR)
        self.assertIn("GEMINI_API_KEY", err)
        self.assertEqual(fake.calls, [])

    # ------------------------------------------------------------------ request shape

    def test_generate_request_payload_shape(self) -> None:
        spec = veo_backdrops.build_generate_request(
            "veo-3.1-fast-generate-preview", "teal mist over bone", "16:9", 8
        )
        self.assertEqual(spec["method"], "POST")
        self.assertEqual(
            spec["url"],
            "https://generativelanguage.googleapis.com/v1beta/models/veo-3.1-fast-generate-preview:predictLongRunning",
        )
        self.assertEqual(
            spec["body"],
            {
                "instances": [{"prompt": "teal mist over bone"}],
                "parameters": {"aspectRatio": "16:9", "durationSeconds": 8, "personGeneration": "dont_allow"},
            },
        )
        self.assertEqual(spec["headers"]["x-goog-api-key"], "<GEMINI_API_KEY>")

    def test_post_request_sent_over_the_wire_matches_the_spec(self) -> None:
        fake = _urlopen_script(json.dumps({"name": "models/veo/operations/op-3"}).encode())
        spec = veo_backdrops.build_generate_request("veo-3.1-fast-generate-preview", "p", "16:9", 8)
        with mock.patch("urllib.request.urlopen", fake):
            name = veo_backdrops.start_generation(spec, "sk-test-SECRET")
        self.assertEqual(name, "models/veo/operations/op-3")
        request = fake.calls[0]
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.full_url, spec["url"])
        self.assertEqual(request.get_header("X-goog-api-key"), "sk-test-SECRET")
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(json.loads(request.data.decode("utf-8")), spec["body"])

    # ------------------------------------------------------------------ dry run

    def test_dry_run_prints_requests_and_plan_without_network_or_ledger_writes(self) -> None:
        fake = _urlopen_script()
        with mock.patch.dict(os.environ, {}, clear=True), mock.patch("urllib.request.urlopen", fake):
            code, out, err = self._run("--dry-run")
        self.assertEqual(code, veo_backdrops.EXIT_OK, err)
        self.assertEqual(fake.calls, [], "dry run must not touch the network")
        self.assertFalse(self.ledger.exists(), "dry run must not write the ledger")
        self.assertFalse(self.out.exists())
        self.assertIn(
            "POST https://generativelanguage.googleapis.com/v1beta/models/veo-3.1-fast-generate-preview:predictLongRunning",
            out,
        )
        self.assertIn("x-goog-api-key: <GEMINI_API_KEY>", out)
        self.assertIn('"personGeneration": "dont_allow"', out)
        self.assertIn('"durationSeconds": 8', out)
        self.assertIn('"aspectRatio": "16:9"', out)
        self.assertIn("bone cathedral, teal mist, static camera", out)
        self.assertIn("dragon skull crypt, slow fog", out)
        self.assertIn("cost/clip=$1.20", out)
        self.assertIn("ledger after this clip $1.20", out)
        self.assertIn("ledger after this clip $2.40", out)
        self.assertIn("dry run: 2 clip(s) would cost $2.40", out)

    def test_dry_run_honours_price_override_and_max_clips(self) -> None:
        with mock.patch("urllib.request.urlopen", _urlopen_script()):
            code, out, _err = self._run("--dry-run", "--price-per-second", "0.40", "--max-clips", "1")
        self.assertEqual(code, veo_backdrops.EXIT_OK)
        self.assertIn("cost/clip=$3.20", out)
        self.assertIn("[1/1] clip_a", out)
        self.assertNotIn("clip_b", out)


if __name__ == "__main__":
    unittest.main()
