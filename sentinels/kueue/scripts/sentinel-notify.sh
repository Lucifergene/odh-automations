#!/usr/bin/env bash
set -euo pipefail

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

UPSTREAM_KUEUE_TAG="${UPSTREAM_KUEUE_TAG:-unknown}"
UPSTREAM_TRAINER_TAG="${UPSTREAM_TRAINER_TAG:-unknown}"
# Pinned versions from VERSIONS files in odh-dashboard (what PRs are tested against).
# If set and different from the upstream tags above, a bump notice is added to the report.
KUEUE_TAG_PINNED="${KUEUE_TAG_PINNED:-}"
TRAINER_TAG_PINNED="${TRAINER_TAG_PINNED:-}"
L1_RESULT="${L1_RESULT:-unknown}"
L2_RESULT="${L2_RESULT:-unknown}"
L3_RESULT="${L3_RESULT:-unknown}"
L2_SUMMARY="${L2_SUMMARY:-}"
L3_SUMMARY="${L3_SUMMARY:-}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-}"

layer_passed() {
  case "$1" in
    success|success-success) return 0 ;;
    *) return 1 ;;
  esac
}

ALL_PASS=true
for STATUS in "${L1_RESULT}" "${L2_RESULT}" "${L3_RESULT}"; do
  if ! layer_passed "${STATUS}"; then
    ALL_PASS=false
    break
  fi
done

REPRO_KUEUE="cd packages/k8s-core && KUEUE_TAG=${UPSTREAM_KUEUE_TAG} npm run kueue:check"
REPRO_TRAINER="cd packages/model-training && TRAINER_TAG=${UPSTREAM_TRAINER_TAG} npm run trainer:check"

# Detect whether the pinned VERSIONS in odh-dashboard are behind what the sentinel just tested.
# A newer upstream is available; the team decides whether to bump based on what their
# RHBoK release ships — the sentinel does not make that call for them.
VERSION_DRIFT_LINES=()
if [[ -n "${KUEUE_TAG_PINNED}" && "${KUEUE_TAG_PINNED}" != "${UPSTREAM_KUEUE_TAG}" ]]; then
  VERSION_DRIFT_LINES+=("Kueue: upstream ${UPSTREAM_KUEUE_TAG} available (pin: ${KUEUE_TAG_PINNED})")
fi
if [[ -n "${TRAINER_TAG_PINNED}" && "${TRAINER_TAG_PINNED}" != "${UPSTREAM_TRAINER_TAG}" ]]; then
  VERSION_DRIFT_LINES+=("Trainer: upstream ${UPSTREAM_TRAINER_TAG} available (pin: ${TRAINER_TAG_PINNED})")
fi
HAS_VERSION_DRIFT=false
VERSION_DRIFT_NOTICE=""
if [[ ${#VERSION_DRIFT_LINES[@]} -gt 0 ]]; then
  HAS_VERSION_DRIFT=true
  VERSION_DRIFT_NOTICE=$(printf '%s\n' "${VERSION_DRIFT_LINES[@]}")
fi

if layer_passed "${L1_RESULT}"; then
  LAYER1_SUMMARY="Kueue ${UPSTREAM_KUEUE_TAG}, Trainer ${UPSTREAM_TRAINER_TAG} — TypeScript types aligned"
else
  LAYER1_SUMMARY=":warning: Type drift — dashboard types no longer match Kueue ${UPSTREAM_KUEUE_TAG} or Trainer ${UPSTREAM_TRAINER_TAG}"
fi
if [[ "${HAS_VERSION_DRIFT}" == "true" ]]; then
  LAYER1_SUMMARY="${LAYER1_SUMMARY} — :information_source: newer upstream available"
fi

if [[ -z "${L2_SUMMARY}" ]]; then
  if layer_passed "${L2_RESULT}"; then
    L2_SUMMARY="all checks passed"
  else
    L2_SUMMARY=":warning: checks failed — see workflow logs"
  fi
fi

if [[ -z "${L3_SUMMARY}" ]]; then
  if layer_passed "${L3_RESULT}"; then
    L3_SUMMARY="all checks passed"
  else
    L3_SUMMARY=":warning: checks failed — see workflow logs"
  fi
fi

if [[ "${ALL_PASS}" == "true" ]]; then
  OVERALL_STATUS="All Clear"
  OVERALL_EMOJI=":white_check_mark:"
  if [[ "${HAS_VERSION_DRIFT}" == "true" ]]; then
    # Tests passed against the newer upstream — informational only.
    # The team decides whether to bump the pin based on what their RHBoK release ships.
    DETAILS="New upstream version available — dashboard is compatible:
${VERSION_DRIFT_NOTICE}
Bump the VERSIONS pin when your RHBoK release adopts the new upstream.
To verify: KUEUE_TAG=${UPSTREAM_KUEUE_TAG} npm run kueue:check (packages/k8s-core)"
  else
    DETAILS=""
  fi
else
  OVERALL_STATUS="Issues Detected"
  OVERALL_EMOJI=":x:"
  DETAILS="Upstream Kueue ${UPSTREAM_KUEUE_TAG} or Trainer ${UPSTREAM_TRAINER_TAG} introduced a breaking change.
Reproduce locally:
• ${REPRO_KUEUE}
• ${REPRO_TRAINER}
Fix: update TypeScript types and CRD fixtures, then bump VERSIONS when RHBoK adopts this version."
  if [[ "${HAS_VERSION_DRIFT}" == "true" ]]; then
    DETAILS="${DETAILS}
New upstream also available — address the breakage above first:
${VERSION_DRIFT_NOTICE}"
  fi
fi

PAYLOAD=$(cat <<EOF
{
  "overall_status": "$(json_escape "${OVERALL_STATUS}")",
  "overall_emoji": "$(json_escape "${OVERALL_EMOJI}")",
  "layer1_summary": "$(json_escape "${LAYER1_SUMMARY}")",
  "layer2_summary": "$(json_escape "${L2_SUMMARY}")",
  "layer3_summary": "$(json_escape "${L3_SUMMARY}")",
  "details": "$(json_escape "${DETAILS}")",
  "workflow_run_url": "$(json_escape "${WORKFLOW_RUN_URL}")"
}
EOF
)

if [[ "${DRY_RUN:-false}" == "true" ]]; then
  printf '%s\n' "${PAYLOAD}"
  exit 0
fi

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::warning::SLACK_WEBHOOK_URL is not set -- skipping Slack notification"
  exit 0
fi

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "${PAYLOAD}" \
  "${SLACK_WEBHOOK_URL}") || true

if [[ "${HTTP_CODE}" -ge 200 && "${HTTP_CODE}" -lt 300 ]]; then
  echo "Slack notification sent successfully (HTTP ${HTTP_CODE})"
else
  echo "::warning::Slack notification failed (HTTP ${HTTP_CODE})"
fi

exit 0
