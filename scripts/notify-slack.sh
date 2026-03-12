#!/usr/bin/env bash
#
# Sends BFF / Llama Stack compatibility test results to Slack via webhook.
#
# Required environment variables:
#   SLACK_WEBHOOK_URL   - Slack Incoming Webhook URL
#   LLS_VERSION         - Llama Stack version that was tested
#   LLS_PINNED_VERSION  - Pinned version from the Makefile
#   REPLAY_RESULT       - "success" | "failure"
#   RECORD_RESULT       - "success" | "failure" | "skipped"
#   WORKFLOW_RUN_URL    - Full URL to the GitHub Actions run
#   TRIGGER             - GitHub event name (schedule, workflow_dispatch, push, pull_request)

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
# Determine status, color, and messaging
# ---------------------------------------------------------------------------

if [[ "$REPLAY_RESULT" == "success" ]]; then
  COLOR="#36a64f"
  HEADER=":white_check_mark: BFF Compatibility: COMPATIBLE"
  RECORDING_FIELD="Not required"
  CONTEXT="Existing test fixtures passed against Llama Stack ${LLS_VERSION}. No action required."
elif [[ "$RECORD_RESULT" == "success" ]]; then
  COLOR="#ff9900"
  HEADER=":warning: BFF Compatibility: COMPATIBLE (recording required)"
  RECORDING_FIELD="Yes — fixtures need updating"
  CONTEXT="Replay fixtures failed but live recording passed. The BFF is compatible with Llama Stack ${LLS_VERSION}, but fixtures need re-recording.\n*Action:* Run \`make llamastack-record\` and commit updated recordings to odh-dashboard."
else
  COLOR="#dc3545"
  HEADER=":x: BFF Compatibility: INCOMPATIBLE"
  RECORDING_FIELD="N/A — both tests failed"
  CONTEXT="Both replay and live recording tests failed against Llama Stack ${LLS_VERSION}. BFF code changes may be needed.\n*Action:* Investigate the workflow run logs."
fi

# ---------------------------------------------------------------------------
# Build Slack Block Kit payload (all values JSON-escaped)
# ---------------------------------------------------------------------------

E_HEADER=$(json_escape "$HEADER")
E_VERSION=$(json_escape "$LLS_VERSION")
E_PINNED=$(json_escape "$LLS_PINNED_VERSION")
E_RECORDING=$(json_escape "$RECORDING_FIELD")
E_TRIGGER=$(json_escape "$TRIGGER")
E_CONTEXT=$(json_escape "$CONTEXT")
E_URL=$(json_escape "$WORKFLOW_RUN_URL")

PAYLOAD=$(cat <<EOF
{
  "attachments": [
    {
      "color": "${COLOR}",
      "blocks": [
        {
          "type": "header",
          "text": {
            "type": "plain_text",
            "text": "Gen AI BFF — Llama Stack Compatibility",
            "emoji": true
          }
        },
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "${E_HEADER}"
          }
        },
        {
          "type": "section",
          "fields": [
            { "type": "mrkdwn", "text": "*Tested Version*\n${E_VERSION}" },
            { "type": "mrkdwn", "text": "*Pinned Version*\n${E_PINNED}" },
            { "type": "mrkdwn", "text": "*Recording Required*\n${E_RECORDING}" },
            { "type": "mrkdwn", "text": "*Trigger*\n${E_TRIGGER}" }
          ]
        },
        {
          "type": "section",
          "text": {
            "type": "mrkdwn",
            "text": "${E_CONTEXT}"
          }
        },
        {
          "type": "actions",
          "elements": [
            {
              "type": "button",
              "text": {
                "type": "plain_text",
                "text": "View Workflow Run",
                "emoji": true
              },
              "url": "${E_URL}"
            }
          ]
        }
      ]
    }
  ]
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
