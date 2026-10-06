#!/usr/bin/env python3
"""Generate looping stage-backdrop clips with the Gemini API's Veo models under a hard budget.

Dependency-free (Python 3.11 stdlib, urllib only).  The API key is read from the
GEMINI_API_KEY environment variable, never from arguments, and is never printed.

    python3 tools/veo_backdrops.py --dry-run                 # show requests + spend plan
    GEMINI_API_KEY=... python3 tools/veo_backdrops.py --max-clips 1

Per clip: POST models/{model}:predictLongRunning, poll the returned operation every
POLL_SECONDS until done (POLL_TIMEOUT_SECONDS cap), download the first generated sample to
<out>/<name>.mp4.  Estimated spend (duration * price-per-second) is recorded in the ledger
(tools/veo_spend.json) BEFORE a request is sent, and a clip whose estimate would push the
ledger past --budget-usd is refused.  See docs/VEO.md.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

API_ROOT = "https://generativelanguage.googleapis.com/v1beta"
KEY_ENV = "GEMINI_API_KEY"
DEFAULT_MODEL = "veo-3.1-fast-generate-preview"
DEFAULT_BUDGET_USD = 28.0
# USD per generated second (Gemini API list prices at time of writing).
PRICE_PER_SECOND = {"fast": 0.15, "standard": 0.40}
POLL_SECONDS = 10.0
POLL_TIMEOUT_SECONDS = 600.0
HTTP_TIMEOUT_SECONDS = 120.0
# Default paths are relative to the repository root (the script's parent's parent).
REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PROMPT_FILE = REPO_ROOT / "tools" / "veo_prompts.json"
DEFAULT_LEDGER = REPO_ROOT / "tools" / "veo_spend.json"
DEFAULT_OUT = REPO_ROOT / "assets" / "video" / "raw"

EXIT_OK = 0
EXIT_ERROR = 1
EXIT_BUDGET = 2


class BudgetExceeded(Exception):
    """Starting this clip would push the ledger past the budget."""


# --------------------------------------------------------------------------- pricing/ledger


def price_for_model(model: str) -> float:
    """Pick the per-second price from the model name: "fast" models vs everything else."""
    return PRICE_PER_SECOND["fast"] if "fast" in model else PRICE_PER_SECOND["standard"]


def estimate_cost(duration_seconds: int, price_per_second: float) -> float:
    return round(duration_seconds * price_per_second, 4)


def load_ledger(path: Path) -> dict:
    if not path.exists():
        return {"spent_usd": 0.0, "clips": []}
    with path.open("r", encoding="utf-8") as handle:
        ledger = json.load(handle)
    ledger.setdefault("spent_usd", 0.0)
    ledger.setdefault("clips", [])
    return ledger


def save_ledger(path: Path, ledger: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as handle:
        json.dump(ledger, handle, indent=2)
        handle.write("\n")


def reserve_spend(ledger: dict, entry: dict, budget_usd: float) -> None:
    """Add `entry` (with its cost_usd) to the ledger or raise BudgetExceeded. Pure: no I/O."""
    projected = round(ledger["spent_usd"] + entry["cost_usd"], 4)
    if projected > budget_usd + 1e-9:
        raise BudgetExceeded(
            f"refusing {entry['name']!r}: spent ${ledger['spent_usd']:.2f} + "
            f"${entry['cost_usd']:.2f} = ${projected:.2f} exceeds budget ${budget_usd:.2f}"
        )
    ledger["spent_usd"] = projected
    ledger["clips"].append(entry)


# --------------------------------------------------------------------------- requests


def build_generate_request(model: str, prompt: str, aspect: str, duration_seconds: int) -> dict:
    """The exact predictLongRunning call, as plain data so tests and --dry-run can inspect it."""
    return {
        "method": "POST",
        "url": f"{API_ROOT}/models/{model}:predictLongRunning",
        "headers": {"Content-Type": "application/json", "x-goog-api-key": f"<{KEY_ENV}>"},
        "body": {
            "instances": [{"prompt": prompt}],
            "parameters": {
                "aspectRatio": aspect,
                "durationSeconds": duration_seconds,
                "personGeneration": "dont_allow",
            },
        },
    }


def _http(method: str, url: str, api_key: str, body: dict | None = None) -> bytes:
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"x-goog-api-key": api_key}
    if data is not None:
        headers["Content-Type"] = "application/json"
    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT_SECONDS) as response:
            return response.read()
    except urllib.error.HTTPError as err:
        # The error body never contains the key; it is safe to surface.
        detail = err.read().decode("utf-8", "replace")[:500]
        raise RuntimeError(f"HTTP {err.code} from {url}: {detail}") from None


def start_generation(spec: dict, api_key: str) -> str:
    """POST the generate request; return the long-running operation name."""
    payload = json.loads(_http("POST", spec["url"], api_key, spec["body"]))
    name = payload.get("name")
    if not name:
        raise RuntimeError(f"predictLongRunning returned no operation name: {payload}")
    return name


def poll_operation(operation_name: str, api_key: str) -> dict:
    """GET v1beta/{operation} every POLL_SECONDS until done; raise on timeout or API error."""
    url = f"{API_ROOT}/{operation_name}"
    deadline = time.monotonic() + POLL_TIMEOUT_SECONDS
    while True:
        payload = json.loads(_http("GET", url, api_key))
        if payload.get("done"):
            if "error" in payload:
                raise RuntimeError(f"operation failed: {payload['error']}")
            return payload
        if time.monotonic() >= deadline:
            raise RuntimeError(f"operation {operation_name} not done after {POLL_TIMEOUT_SECONDS:.0f}s")
        time.sleep(POLL_SECONDS)


def video_uri(operation: dict) -> str:
    try:
        return operation["response"]["generateVideoResponse"]["generatedSamples"][0]["video"]["uri"]
    except (KeyError, IndexError, TypeError):
        raise RuntimeError(
            "operation finished without a video sample (safety filter?): "
            + json.dumps(operation.get("response", {}))[:500]
        ) from None


def download(uri: str, api_key: str, dest: Path) -> int:
    # Authenticate with the header rather than ?key=... so the key never lands in a URL/log.
    data = _http("GET", uri, api_key)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    return len(data)


# --------------------------------------------------------------------------- CLI


def load_prompts(path: Path) -> list[dict]:
    with path.open("r", encoding="utf-8") as handle:
        prompts = json.load(handle)
    if not isinstance(prompts, list) or not all(
        isinstance(p, dict) and p.get("name") and p.get("prompt") for p in prompts
    ):
        raise SystemExit(f"{path}: expected a JSON list of {{\"name\", \"prompt\"}} objects")
    return prompts


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--prompt-file", type=Path, default=DEFAULT_PROMPT_FILE)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--max-clips", type=int, default=None, help="generate at most N clips")
    parser.add_argument("--budget-usd", type=float, default=DEFAULT_BUDGET_USD)
    parser.add_argument(
        "--price-per-second",
        type=float,
        default=None,
        help=f"override the price table {PRICE_PER_SECOND} (USD per generated second)",
    )
    parser.add_argument("--duration", type=int, default=8, help="clip length in seconds")
    parser.add_argument("--aspect", default="16:9")
    parser.add_argument("--ledger", type=Path, default=DEFAULT_LEDGER, help="spend ledger JSON")
    parser.add_argument("--dry-run", action="store_true", help="print requests and spend plan; no network")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    price = args.price_per_second if args.price_per_second is not None else price_for_model(args.model)
    prompts = load_prompts(args.prompt_file)
    if args.max_clips is not None:
        prompts = prompts[: args.max_clips]
    ledger = load_ledger(args.ledger)
    cost = estimate_cost(args.duration, price)

    api_key = os.environ.get(KEY_ENV, "")
    if not args.dry_run and not api_key:
        print(f"error: {KEY_ENV} is not set in the environment", file=sys.stderr)
        return EXIT_ERROR

    print(
        f"model={args.model} price=${price:.2f}/s duration={args.duration}s "
        f"cost/clip=${cost:.2f} spent=${ledger['spent_usd']:.2f} budget=${args.budget_usd:.2f} "
        f"ledger={args.ledger}"
    )

    for entry_index, item in enumerate(prompts, start=1):
        spec = build_generate_request(args.model, item["prompt"], args.aspect, args.duration)
        entry = {
            "name": item["name"],
            "model": args.model,
            "duration_seconds": args.duration,
            "cost_usd": cost,
            "status": "planned" if args.dry_run else "started",
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        try:
            reserve_spend(ledger, entry, args.budget_usd)
        except BudgetExceeded as err:
            print(f"BUDGET: {err}", file=sys.stderr)
            return EXIT_BUDGET

        dest = args.out / f"{item['name']}.mp4"
        print(f"\n[{entry_index}/{len(prompts)}] {item['name']} -> {dest}")
        print(f"  {spec['method']} {spec['url']}")
        for header, value in spec["headers"].items():
            print(f"  {header}: {value}")
        print("  " + json.dumps(spec["body"], indent=2).replace("\n", "\n  "))
        print(f"  estimated cost ${cost:.2f}; ledger after this clip ${ledger['spent_usd']:.2f}")
        if args.dry_run:
            continue

        # Persist the reservation before the network call: a crash mid-generation still counts.
        save_ledger(args.ledger, ledger)
        try:
            operation_name = start_generation(spec, api_key)
            entry["operation"] = operation_name
            print(f"  operation {operation_name}; polling every {POLL_SECONDS:.0f}s")
            operation = poll_operation(operation_name, api_key)
            size = download(video_uri(operation), api_key, dest)
            entry["status"] = "done"
            entry["bytes"] = size
            print(f"  wrote {dest} ({size} bytes)")
        except RuntimeError as err:
            entry["status"] = "failed"
            entry["error"] = str(err)
            save_ledger(args.ledger, ledger)
            print(f"  FAILED: {err}", file=sys.stderr)
            return EXIT_ERROR
        save_ledger(args.ledger, ledger)

    if args.dry_run:
        print(f"\ndry run: {len(prompts)} clip(s) would cost ${cost * len(prompts):.2f}; ledger not written")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
