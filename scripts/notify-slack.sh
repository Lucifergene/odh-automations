#!/usr/bin/env bash
#
# Sends BFF / Llama Stack compatibility test results to a Slack Workflow
# Builder webhook. Handles results for stable (pypi.org) and/or dev
# (test.pypi.org) builds, combining them into a single notification.
#
# Required environment variables:
#   SLACK_WEBHOOK_URL   - Slack Workflow Builder webhook URL
#   WORKFLOW_RUN_URL    - Full URL to the GitHub Actions run
#   TRIGGER             - GitHub event name
#
# Optional (per-source) environment variables:
#   STABLE_VERSION, STABLE_STATUS, STABLE_RECORDING, STABLE_REPLAY, STABLE_RECORD, STABLE_PINNED
#   DEV_VERSION, DEV_STATUS, DEV_RECORDING, DEV_REPLAY, DEV_RECORD, DEV_PINNED
#   POST_TO_CHANNEL - "true" to post to Slack channel, "false" to skip (default: "false")
#
# Slack Workflow Builder setup:
#   1. Create a workflow with trigger "Starts with a webhook"
#   2. Define text variables: overall_status, overall_emoji, stable_summary,
#      dev_summary, details, trigger, workflow_run_url, post_to_channel
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
for VAR in WORKFLOW_RUN_URL TRIGGER; do
  if [[ -z "${!VAR:-}" ]]; then
    MISSING+=("$VAR")
  fi
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
  echo "::warning::Missing required env vars: ${MISSING[*]} -- skipping Slack notification"
  exit 0
fi

if [[ -z "${STABLE_VERSION:-}" && -z "${DEV_VERSION:-}" ]]; then
  echo "::warning::No stable or dev results found -- skipping Slack notification"
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
# Build per-source summaries
# ---------------------------------------------------------------------------

format_summary() {
  local version="$1" status="$2" recording="$3"
  if [[ -z "$version" ]]; then
    printf "N/A (not tested)"
    return
  fi
  local label
  if [[ "$status" == "compatible" && "$recording" == "false" ]]; then
    label="COMPATIBLE"
  elif [[ "$status" == "compatible" && "$recording" == "true" ]]; then
    label="COMPATIBLE (recording required)"
  else
    label="INCOMPATIBLE"
  fi
  printf "%s: %s" "$version" "$label"
}

format_detail() {
  local source_label="$1" version="$2" status="$3" recording="$4"
  if [[ -z "$version" ]]; then
    return
  fi
  if [[ "$status" == "compatible" && "$recording" == "false" ]]; then
    printf "[%s] %s passed -- no action required." "$source_label" "$version"
  elif [[ "$status" == "compatible" && "$recording" == "true" ]]; then
    printf "[%s] %s passed with recording -- fixtures need re-recording. Run make llamastack-record and commit." "$source_label" "$version"
  else
    printf "[%s] %s failed -- BFF code changes may be needed. Check workflow logs." "$source_label" "$version"
  fi
}

STABLE_SUMMARY=$(format_summary "${STABLE_VERSION:-}" "${STABLE_STATUS:-}" "${STABLE_RECORDING:-}")
DEV_SUMMARY=$(format_summary "${DEV_VERSION:-}" "${DEV_STATUS:-}" "${DEV_RECORDING:-}")

DETAILS=""
STABLE_DETAIL=$(format_detail "Stable" "${STABLE_VERSION:-}" "${STABLE_STATUS:-}" "${STABLE_RECORDING:-}")
DEV_DETAIL=$(format_detail "Dev" "${DEV_VERSION:-}" "${DEV_STATUS:-}" "${DEV_RECORDING:-}")

if [[ -n "$STABLE_DETAIL" && -n "$DEV_DETAIL" ]]; then
  DETAILS="${STABLE_DETAIL} ${DEV_DETAIL}"
elif [[ -n "$STABLE_DETAIL" ]]; then
  DETAILS="$STABLE_DETAIL"
elif [[ -n "$DEV_DETAIL" ]]; then
  DETAILS="$DEV_DETAIL"
fi

# ---------------------------------------------------------------------------
# Determine overall status
# ---------------------------------------------------------------------------

HAS_INCOMPATIBLE=false
HAS_RECORDING=false

for STATUS_VAR in STABLE_STATUS DEV_STATUS; do
  VAL="${!STATUS_VAR:-}"
  if [[ "$VAL" == "incompatible" ]]; then
    HAS_INCOMPATIBLE=true
  fi
done

for REC_VAR in STABLE_RECORDING DEV_RECORDING; do
  VAL="${!REC_VAR:-}"
  if [[ "$VAL" == "true" ]]; then
    HAS_RECORDING=true
  fi
done

if [[ "$HAS_INCOMPATIBLE" == "true" ]]; then
  OVERALL_STATUS="Incompatible"
  OVERALL_EMOJI=":x:"
elif [[ "$HAS_RECORDING" == "true" ]]; then
  OVERALL_STATUS="Compatible (recording required)"
  OVERALL_EMOJI=":warning:"
else
  OVERALL_STATUS="All Compatible"
  OVERALL_EMOJI=":white_check_mark:"
fi

# ---------------------------------------------------------------------------
# Build flat JSON payload for Slack Workflow Builder
# ---------------------------------------------------------------------------

PAYLOAD=$(cat <<EOF
{
  "overall_status": "$(json_escape "$OVERALL_STATUS")",
  "overall_emoji": "$(json_escape "$OVERALL_EMOJI")",
  "stable_summary": "$(json_escape "$STABLE_SUMMARY")",
  "dev_summary": "$(json_escape "$DEV_SUMMARY")",
  "details": "$(json_escape "$DETAILS")",
  "trigger": "$(json_escape "$TRIGGER")",
  "workflow_run_url": "$(json_escape "$WORKFLOW_RUN_URL")",
  "post_to_channel": "$(json_escape "${POST_TO_CHANNEL:-false}")"
}
EOF
)

# ---------------------------------------------------------------------------
# Send to Slack
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
