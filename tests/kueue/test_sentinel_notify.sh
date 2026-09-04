#!/usr/bin/env bash
# Validates sentinel-notify.sh produces well-formed JSON for all outcome combos.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTIFY_SCRIPT="${ROOT_DIR}/scripts/kueue/sentinel-notify.sh"

EXPECTED_KEYS='["details","layer1_summary","layer2_summary","layer3_summary","overall_emoji","overall_status","workflow_run_url"]'

if [[ ! -x "${NOTIFY_SCRIPT}" ]]; then
  chmod +x "${NOTIFY_SCRIPT}"
fi

validate_payload() {
  local payload="$1"
  python3 - <<'PY' "${payload}" "${EXPECTED_KEYS}"
import json
import sys

payload = json.loads(sys.argv[1])
expected_keys = json.loads(sys.argv[2])

actual_keys = sorted(payload.keys())
if actual_keys != sorted(expected_keys):
    raise SystemExit(f"unexpected keys: {actual_keys}, expected: {sorted(expected_keys)}")

if "action" in payload:
    raise SystemExit("action field must not be present")

all_pass = (
    payload["layer1_summary"].startswith(":white_check_mark:")
    and payload["layer2_summary"].startswith(":white_check_mark:")
    and payload["layer3_summary"].startswith(":white_check_mark:")
)
if all_pass and payload["details"] != "":
    raise SystemExit("details must be empty when all layers pass")

if not all_pass and payload["details"] == "":
    raise SystemExit("details must be set when any layer fails")

if not all_pass and "Reproduce locally:" not in payload["details"]:
    raise SystemExit("failure details must include reproduce instructions")
PY
}

for L1 in success failure; do
  for L2 in success failure; do
    for L3 in success failure; do
      PAYLOAD="$(UPSTREAM_KUEUE_TAG=v0.20.0 UPSTREAM_TRAINER_TAG=v2.5.0 \
        L1_RESULT="${L1}-${L1}" L2_RESULT="${L2}" L3_RESULT="${L3}" \
        WORKFLOW_RUN_URL=https://github.com/example/actions/runs/1 \
        DRY_RUN=true bash "${NOTIFY_SCRIPT}")"
      validate_payload "${PAYLOAD}" \
        && echo "PASS: L1=${L1} L2=${L2} L3=${L3}" \
        || { echo "FAIL: L1=${L1} L2=${L2} L3=${L3}"; exit 1; }
    done
  done
done

echo "All 8 combinations produce valid 7-field JSON."
