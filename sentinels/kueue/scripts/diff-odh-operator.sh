#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/kueue-sentinel-results}"
mkdir -p "${OUTPUT_DIR}"

OPERATOR_DIR="${OUTPUT_DIR}/odh-operator"
SUMMARY_FILE="${OUTPUT_DIR}/operator-summary.txt"
rm -rf "${OPERATOR_DIR}"

write_summary() {
  local summary="$1"
  echo "operator_summary=${summary}" > "${SUMMARY_FILE}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "summary=${summary}" >> "${GITHUB_OUTPUT}"
  fi
}

if git clone --depth 50 https://github.com/opendatahub-io/opendatahub-operator "${OPERATOR_DIR}"; then
  pushd "${OPERATOR_DIR}" >/dev/null
  DIFF_OUTPUT="$(git log -n 20 --name-only --pretty=format: -- \
    | rg -i 'kueue|hardwareprofile|workload' || true \
    | sort -u \
    | head -20 \
    | tr '\n' ' ')"
  popd >/dev/null

  if [[ -n "${DIFF_OUTPUT// }" ]]; then
    write_summary "Recent operator commits touched: ${DIFF_OUTPUT}"
  else
    write_summary "No recent operator commits touching Kueue/HWP paths"
  fi
else
  write_summary "Failed to clone opendatahub-operator for diff"
fi
