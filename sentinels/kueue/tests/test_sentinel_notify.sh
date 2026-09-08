#!/usr/bin/env bash
# Validates sentinel-notify.sh produces well-formed JSON for all outcome combos.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIFY_SCRIPT="${ROOT_DIR}/scripts/sentinel-notify.sh"

EXPECTED_KEYS='["details","layer1_summary","layer2_summary","layer3_summary","overall_emoji","overall_status","workflow_run_url"]'

if [[ ! -x "${NOTIFY_SCRIPT}" ]]; then
  chmod +x "${NOTIFY_SCRIPT}"
fi

validate_payload() {
  local payload="$1"
  local has_version_drift="${2:-false}"  # "true" when KUEUE_TAG_PINNED/TRAINER_TAG_PINNED differ from upstream
  python3 - <<'PY' "${payload}" "${EXPECTED_KEYS}" "${has_version_drift}"
import json
import sys

payload = json.loads(sys.argv[1])
expected_keys = json.loads(sys.argv[2])
has_drift = sys.argv[3] == "true"

actual_keys = sorted(payload.keys())
if actual_keys != sorted(expected_keys):
    raise SystemExit(f"unexpected keys: {actual_keys}, expected: {sorted(expected_keys)}")

if "action" in payload:
    raise SystemExit("action field must not be present")

all_pass = payload["overall_emoji"] == ":white_check_mark:"

if all_pass and payload["overall_status"] != "All Clear":
    raise SystemExit("overall_status must be All Clear when all layers pass")

if not all_pass and payload["overall_status"] != "Issues Detected":
    raise SystemExit("overall_status must be Issues Detected when any layer fails")

# details rules depend on pass/fail state AND version drift
if all_pass and not has_drift and payload["details"] != "":
    raise SystemExit("details must be empty when all layers pass and no version drift")

if all_pass and has_drift and payload["details"] == "":
    raise SystemExit("details must include bump instructions when all layers pass but VERSIONS pin is stale")

if all_pass and has_drift and "VERSIONS pin is out of date" not in payload["details"]:
    raise SystemExit("details must mention VERSIONS pin when version drift exists")

if not all_pass and payload["details"] == "":
    raise SystemExit("details must be set when any layer fails")

if not all_pass and "Reproduce locally:" not in payload["details"]:
    raise SystemExit("failure details must include reproduce instructions")

if "`" in payload["details"]:
    raise SystemExit("details must not include backticks")

layer_summaries = [
    payload["layer1_summary"],
    payload["layer2_summary"],
    payload["layer3_summary"],
]

if all_pass and any(":warning:" in summary for summary in layer_summaries):
    raise SystemExit("layer summaries must not include :warning: when all layers pass")

if not all_pass and not any(":warning:" in summary for summary in layer_summaries):
    raise SystemExit("at least one layer summary must include :warning: when any layer fails")

if "*" in "".join(layer_summaries):
    raise SystemExit("layer summaries must not include mrkdwn asterisks")

# Version drift: layer1_summary must signal the stale pin
if has_drift and ":arrow_up: VERSIONS pin stale" not in payload["layer1_summary"]:
    raise SystemExit("layer1_summary must note stale VERSIONS pin when version drift exists")

if not has_drift and ":arrow_up:" in payload["layer1_summary"]:
    raise SystemExit("layer1_summary must not mention pin bump when versions are in sync")
PY
}

# --- 8 combinations: no version drift (pinned == upstream, or not set) ---
for L1 in success failure; do
  for L2 in success failure; do
    for L3 in success failure; do
      if [[ "${L1}" == "success" ]]; then
        L1_RESULT="success-success"
      else
        L1_RESULT="failure"
      fi

      PAYLOAD="$(UPSTREAM_KUEUE_TAG=v0.20.0 UPSTREAM_TRAINER_TAG=v2.5.0 \
        L1_RESULT="${L1_RESULT}" L2_RESULT="${L2}" L3_RESULT="${L3}" \
        WORKFLOW_RUN_URL=https://github.com/example/actions/runs/1 \
        DRY_RUN=true bash "${NOTIFY_SCRIPT}")"
      validate_payload "${PAYLOAD}" "false" \
        && echo "PASS (no-drift): L1=${L1} L2=${L2} L3=${L3}" \
        || { echo "FAIL (no-drift): L1=${L1} L2=${L2} L3=${L3}"; exit 1; }
    done
  done
done

echo "All 8 no-drift combinations produce valid 7-field JSON."

# --- 8 combinations: version drift (VERSIONS pin is behind upstream) ---
for L1 in success failure; do
  for L2 in success failure; do
    for L3 in success failure; do
      if [[ "${L1}" == "success" ]]; then
        L1_RESULT="success-success"
      else
        L1_RESULT="failure"
      fi

      PAYLOAD="$(UPSTREAM_KUEUE_TAG=v0.20.0 UPSTREAM_TRAINER_TAG=v2.5.0 \
        KUEUE_TAG_PINNED=v0.18.7 TRAINER_TAG_PINNED=v2.3.0 \
        L1_RESULT="${L1_RESULT}" L2_RESULT="${L2}" L3_RESULT="${L3}" \
        WORKFLOW_RUN_URL=https://github.com/example/actions/runs/1 \
        DRY_RUN=true bash "${NOTIFY_SCRIPT}")"
      validate_payload "${PAYLOAD}" "true" \
        && echo "PASS (drift): L1=${L1} L2=${L2} L3=${L3}" \
        || { echo "FAIL (drift): L1=${L1} L2=${L2} L3=${L3}"; exit 1; }
    done
  done
done

echo "All 8 drift combinations produce valid 7-field JSON."
echo "All 16 combinations passed."
