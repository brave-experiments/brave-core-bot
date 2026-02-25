#!/bin/bash
# Signal notification helper - sends a message via signal-cli
# Usage: ./scripts/signal-notify.sh "Your message here"
#
# Requires environment variables (set in .envrc):
#   SIGNAL_SENDER    - Your registered Signal number (e.g., +14155551234)
#   SIGNAL_RECIPIENT - Number to send notifications to (e.g., +14155559876)
#
# Gracefully does nothing if signal-cli is not installed or env vars are unset.

set -euo pipefail

MESSAGE="${1:-}"

if [[ -z "$MESSAGE" ]]; then
  exit 0
fi

# Skip silently if not configured
if [[ -z "${SIGNAL_SENDER:-}" ]] || [[ -z "${SIGNAL_RECIPIENT:-}" ]]; then
  exit 0
fi

# Skip silently if signal-cli not available
if ! command -v signal-cli &>/dev/null; then
  exit 0
fi

# Send message, suppress errors to avoid breaking callers
signal-cli -u "$SIGNAL_SENDER" send -m "$MESSAGE" "$SIGNAL_RECIPIENT" &>/dev/null || true
