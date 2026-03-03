#!/bin/bash
# Signal notification helper - sends a message via signal-cli
# Usage: ./scripts/signal-notify.sh "Your message here"
#        ./scripts/signal-notify.sh "Reply text" --quote-timestamp 123456 --quote-author "+1234" --quote-message "Original"
#
# Requires environment variables (set in .envrc):
#   SIGNAL_SENDER    - Your registered Signal number (e.g., +14155551234)
#   SIGNAL_RECIPIENT - Number to send notifications to (e.g., +14155559876)
#
# GUIDELINE: Always include a relevant link (PR URL, issue URL, etc.) in the
# message when reporting on a specific item, so the recipient can navigate to it.
#
# Gracefully does nothing if signal-cli is not installed or env vars are unset.

set -euo pipefail

MESSAGE="${1:-}"

if [[ -z "$MESSAGE" ]]; then
  exit 0
fi

shift

# Parse optional quote parameters
QUOTE_TIMESTAMP=""
QUOTE_AUTHOR=""
QUOTE_MESSAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quote-timestamp)
      QUOTE_TIMESTAMP="$2"
      shift 2
      ;;
    --quote-author)
      QUOTE_AUTHOR="$2"
      shift 2
      ;;
    --quote-message)
      QUOTE_MESSAGE="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Skip silently if not configured
if [[ -z "${SIGNAL_SENDER:-}" ]] || [[ -z "${SIGNAL_RECIPIENT:-}" ]]; then
  exit 0
fi

# Skip silently if signal-cli not available
if ! command -v signal-cli &>/dev/null; then
  exit 0
fi

# Build quote arguments if all required fields are present
QUOTE_ARGS=()
if [[ -n "$QUOTE_TIMESTAMP" ]] && [[ -n "$QUOTE_AUTHOR" ]]; then
  QUOTE_ARGS+=(--quote-timestamp "$QUOTE_TIMESTAMP" --quote-author "$QUOTE_AUTHOR")
  if [[ -n "$QUOTE_MESSAGE" ]]; then
    QUOTE_ARGS+=(--quote-message "$QUOTE_MESSAGE")
  fi
fi

# Send message, suppress errors to avoid breaking callers
signal-cli -u "$SIGNAL_SENDER" send -m "$MESSAGE" "${QUOTE_ARGS[@]}" "$SIGNAL_RECIPIENT" &>/dev/null || true
