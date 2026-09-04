#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-/tmp/kueue-sentinel-results}"
mkdir -p "${OUTPUT_DIR}"

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
L1_RESULT="${L1_RESULT:-unknown}"
L2_RESULT="${L2_RESULT:-unknown}"
L3_RESULT="${L3_RESULT:-unknown}"
WORKFLOW_RUN_URL="${WORKFLOW_RUN_URL:-}"

layer_icon() {
  case "$1" in
    success) printf ':white_check_mark:' ;;
    failure|fail|error) printf ':x:' ;;
    *) printf ':grey_question:' ;;
  esac
}

L1_ICON="$(layer_icon "${L1_RESULT%%-*}" 2>/dev/null || layer_icon "${L1_RESULT}")"
L2_ICON="$(layer_icon "${L2_RESULT}")"
L3_ICON="$(layer_icon "${L3_RESULT}")"

ALL_PASS=true
for STATUS in "${L1_RESULT}" "${L2_RESULT}" "${L3_RESULT}"; do
  if [[ "${STATUS}" == "failure" || "${STATUS}" == "fail" || "${STATUS}" == "error" ]]; then
    ALL_PASS=false
    break
  fi
done

if [[ "${ALL_PASS}" == "true" ]]; then
  OVERALL_STATUS="Kueue Sentinel — All Clear"
  OVERALL_EMOJI=":white_check_mark:"
  LAYER1_LINE="Layer 1 · Schema Analysis    ${L1_ICON}  No changes (Kueue ${UPSTREAM_KUEUE_TAG}, Trainer ${UPSTREAM_TRAINER_TAG})"
  LAYER2_LINE="Layer 2 · API Dry-Run        ${L2_ICON}  All dry-run tests passed"
  LAYER3_LINE="Layer 3 · Integration Smoke  ${L3_ICON}  Submit/pause/resume/scale-immutable/delete OK"
else
  OVERALL_STATUS="Kueue Sentinel — Issues Detected"
  OVERALL_EMOJI=":x:"
  LAYER1_LINE="Layer 1 · Schema Analysis    ${L1_ICON}  Kueue ${UPSTREAM_KUEUE_TAG} | Trainer ${UPSTREAM_TRAINER_TAG} | result=${L1_RESULT}"
  LAYER2_LINE="Layer 2 · API Dry-Run        ${L2_ICON}  result=${L2_RESULT}"
  LAYER3_LINE="Layer 3 · Integration Smoke  ${L3_ICON}  result=${L3_RESULT}"
fi

ACTION_KUEUE="cd packages/k8s-core && KUEUE_TAG=${UPSTREAM_KUEUE_TAG} npm run kueue:check"
ACTION_TRAINER="cd packages/model-training && TRAINER_TAG=${UPSTREAM_TRAINER_TAG} npm run trainer:check"
ACTION="${ACTION_KUEUE} | ${ACTION_TRAINER}"

DETAILS="${LAYER1_LINE}
${LAYER2_LINE}
${LAYER3_LINE}
⚡ To validate:
  ${ACTION_KUEUE}
  ${ACTION_TRAINER}
🔗 ${WORKFLOW_RUN_URL}"

PAYLOAD=$(cat <<EOF
{
  "overall_status": "$(json_escape "${OVERALL_STATUS}")",
  "overall_emoji": "$(json_escape "${OVERALL_EMOJI}")",
  "layer1_summary": "$(json_escape "${LAYER1_LINE}")",
  "layer2_summary": "$(json_escape "${LAYER2_LINE}")",
  "layer3_summary": "$(json_escape "${LAYER3_LINE}")",
  "details": "$(json_escape "${DETAILS}")",
  "action": "$(json_escape "${ACTION}")",
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
