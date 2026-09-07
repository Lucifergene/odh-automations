#!/usr/bin/env bash
# Writes rich per-test Markdown tables to $GITHUB_STEP_SUMMARY from layer JSON results.
set -euo pipefail

RESULTS_DIR="${RESULTS_DIR:-/tmp/kueue-sentinel-results}"
SUMMARY_FILE="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

python3 - "${RESULTS_DIR}" "${SUMMARY_FILE}" <<'PY'
import json
import sys
from pathlib import Path

results_dir = Path(sys.argv[1])
summary_file = Path(sys.argv[2])

layers = [
    (
        "🔬 Layer 2 — API Dry-run",
        results_dir / "layer2-results.json",
    ),
    (
        "🧪 Layer 3 — Integration Smoke",
        results_dir / "layer3-results.json",
    ),
]

lines: list[str] = []

for title, json_path in layers:
    if not json_path.is_file():
        lines.append(f"## {title}")
        lines.append("")
        lines.append("_No result file found — tests may not have run._")
        lines.append("")
        continue

    with json_path.open(encoding="utf-8") as handle:
        data = json.load(handle)

    tests = data.get("tests", [])
    passed = sum(1 for test in tests if test.get("status") == "pass")
    total = len(tests)
    lines.append(f"## {title} ({passed}/{total} passed)")
    lines.append("")
    lines.append("| Test | Status | Detail |")
    lines.append("|------|--------|--------|")

    for test in tests:
        status = test.get("status", "unknown")
        icon = "✅ PASS" if status == "pass" else "❌ FAIL"
        detail = str(test.get("detail", "")).replace("|", "\\|")
        lines.append(f"| {test.get('test', 'unknown')} | {icon} | {detail} |")

    lines.append("")

summary_file.parent.mkdir(parents=True, exist_ok=True)
with summary_file.open("a", encoding="utf-8") as handle:
    handle.write("\n".join(lines))
    handle.write("\n")
PY
