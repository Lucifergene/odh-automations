#!/usr/bin/env bash
# Validates sentinel-notify.sh produces well-formed JSON for all outcome combos.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
NOTIFY_SCRIPT="${ROOT_DIR}/scripts/kueue/sentinel-notify.sh"

if [[ ! -x "${NOTIFY_SCRIPT}" ]]; then
  chmod +x "${NOTIFY_SCRIPT}"
fi

for L1 in success failure; do
  for L2 in success failure; do
    for L3 in success failure; do
      UPSTREAM_KUEUE_TAG=v0.20.0 UPSTREAM_TRAINER_TAG=v2.5.0 \
        L1_RESULT="${L1}-${L1}" L2_RESULT="${L2}" L3_RESULT="${L3}" \
        DRY_RUN=true bash "${NOTIFY_SCRIPT}" | python3 -m json.tool > /dev/null \
        && echo "PASS: L1=${L1} L2=${L2} L3=${L3}" \
        || { echo "FAIL: L1=${L1} L2=${L2} L3=${L3}"; exit 1; }
    done
  done
done

echo "All 8 combinations produce valid JSON."
