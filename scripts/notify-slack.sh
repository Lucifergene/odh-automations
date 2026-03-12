#!/usr/bin/env bash
#
# Sends BFF / Llama Stack compatibility test results to a Slack Workflow
# Builder webhook. The webhook expects flat JSON variables that are then
# composed into a message by the Workflow Builder "Send a message" step.
#
# Required environment variables:
#   SLACK_WEBHOOK_URL   - Slack Workflow Builder webhook URL
#   LLS_VERSION         - Llama Stack version that was tested
#   LLS_PINNED_VERSION  - Pinned version from the Makefile
#   REPLAY_RESULT       - "success" | "failure"
#   RECORD_RESULT       - "success" | "failure" | "skipped"
#   WORKFLOW_RUN_URL    - Full URL to the GitHub Actions run
#   TRIGGER             - GitHub event name (schedule, workflow_dispatch, push, pull_request)
#
# Slack Workflow Builder setup:
#   1. Create a workflow with trigger "Starts with a webhook"
#   2. Define text variables: status, status_emoji, tested_version,
#      pinned_version, recording_required, trigger, context, workflow_run_url
#   3. Add a "Send a message" step using those variables in the template

set -euo pipefail

if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
  echo "::warning::SLACK_WEBHOOK_URL is not set -- skipping Slack notification"
  exit 0
fi

# ---------------------------------------------------------------------------
# Validate required inputs
# ---------------------------------------------------------------------------

MISSING=()
for VAR in REPLAY_RESULT RECORD_RESULT LLS_VERSION LLS_PINNED_VERSION WORKFLOW_RUN_URL TRIGGER; do
  if [[ -z "${!VAR:-}" ]]; then
    MISSING+=("$VAR")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "::warning::Missing required env vars: ${MISSING[*]} -- skipping Slack notification"
  exit 0
fi

# ---------------------------------------------------------------------------
# JSON-safe escaping helper
# ---------------------------------------------------------------------------

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# ---------------------------------------------------------------------------
# Determine status and messaging
# ---------------------------------------------------------------------------

if [[ "$REPLAY_RESULT" == "success" ]]; then
  STATUS="COMPATIBLE"
  STATUS_EMOJI=":white_check_mark:"
  RECORDING_FIELD="Not required"
  CONTEXT="Existing test fixtures passed against Llama Stack ${LLS_VERSION}. No action required."
elif [[ "$RECORD_RESULT" == "success" ]]; then
  STATUS="COMPATIBLE (recording required)"
  STATUS_EMOJI=":warning:"
  RECORDING_FIELD="Yes -- fixtures need updating"
  CONTEXT="Replay fixtures failed but live recording passed. The BFF is compatible with Llama Stack ${LLS_VERSION}, but fixtures need re-recording. Action: Run make llamastack-record and commit updated recordings to odh-dashboard."
else
  STATUS="INCOMPATIBLE"
  STATUS_EMOJI=":x:"
  RECORDING_FIELD="N/A -- both tests failed"
  CONTEXT="Both replay and live recording tests failed against Llama Stack ${LLS_VERSION}. BFF code changes may be needed. Action: Investigate the workflow run logs."
fi

# ---------------------------------------------------------------------------
# Build flat JSON payload for Slack Workflow Builder (all values escaped)
# ---------------------------------------------------------------------------

PAYLOAD=$(cat <<EOF
{
  "status": "$(json_escape "$STATUS")",
  "status_emoji": "$(json_escape "$STATUS_EMOJI")",
  "tested_version": "$(json_escape "$LLS_VERSION")",
  "pinned_version": "$(json_escape "$LLS_PINNED_VERSION")",
  "recording_required": "$(json_escape "$RECORDING_FIELD")",
  "trigger": "$(json_escape "$TRIGGER")",
  "context": "$(json_escape "$CONTEXT")",
  "workflow_run_url": "$(json_escape "$WORKFLOW_RUN_URL")"
}
EOF
)

# ---------------------------------------------------------------------------
# Send to Slack — failure here should never break the CI job
# ---------------------------------------------------------------------------

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" \
  "$SLACK_WEBHOOK_URL") || true

if [[ "$HTTP_CODE" -ge 200 && "$HTTP_CODE" -lt 300 ]]; then
  echo "Slack notification sent successfully (HTTP ${HTTP_CODE})"
else
  echo "::warning::Slack notification failed (HTTP ${HTTP_CODE})"
fi

exit 0
