#!/usr/bin/env python3
"""Compute short Slack summaries from layer2/layer3 JSON result files."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path


def summarize_layer(
    json_file: Path,
    pass_context: str,
    *,
    fallback_failed: bool,
) -> str:
    if not json_file.is_file():
        if fallback_failed:
            return ":warning: checks failed — see workflow logs"
        return "all checks passed"

    with json_file.open(encoding="utf-8") as handle:
        data = json.load(handle)

    tests = data.get("tests", [])
    total = len(tests)
    failed = [test["test"] for test in tests if test.get("status") == "fail"]

    if not failed:
        return f"{total} of {total} checks passed ({pass_context})"

    return f":warning: {len(failed)} of {total} checks failed: {', '.join(failed)}"


def main() -> int:
    results_dir = Path(os.environ.get("RESULTS_DIR", "/tmp/kueue-sentinel-results"))
    l2_failed = os.environ.get("L2_RESULT", "") == "failure"
    l3_failed = os.environ.get("L3_RESULT", "") == "failure"

    l2_summary = summarize_layer(
        results_dir / "layer2-results.json",
        "Workload, TrainJob, immutability",
        fallback_failed=l2_failed,
    )
    l3_summary = summarize_layer(
        results_dir / "layer3-results.json",
        "admission, lifecycle, pause/resume, cleanup",
        fallback_failed=l3_failed,
    )

    print(f"l2_summary={l2_summary}")
    print(f"l3_summary={l3_summary}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
