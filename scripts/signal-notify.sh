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
SEND_OUTPUT=$(signal-cli -u "$SIGNAL_SENDER" send -m "$MESSAGE" "${QUOTE_ARGS[@]}" "$SIGNAL_RECIPIENT" 2>/dev/null || true)

# Save outgoing message to history for recursive quote chain resolution
HISTORY_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/.ignore/signal-message-history.json"
# Extract timestamp from signal-cli output (JSON with timestamp field)
SEND_TIMESTAMP=$(echo "$SEND_OUTPUT" | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line:
        continue
    try:
        data = json.loads(line)
        ts = data.get('timestamp') or data.get('result', {}).get('timestamp')
        if ts:
            print(ts)
            break
    except (json.JSONDecodeError, AttributeError):
        continue
" 2>/dev/null || true)

if [[ -n "$SEND_TIMESTAMP" ]]; then
  python3 -c "
import json, os, sys
history_file = sys.argv[1]
timestamp = sys.argv[2]
message = sys.argv[3]
quote_ts = sys.argv[4] if len(sys.argv) > 4 else ''

history = {}
if os.path.exists(history_file):
    try:
        with open(history_file) as f:
            history = json.load(f)
    except (json.JSONDecodeError, IOError):
        history = {}

entry = {'text': message}
if quote_ts:
    entry['quote_id'] = int(quote_ts)
history[timestamp] = entry

# Prune to last 2000 entries
if len(history) > 2000:
    sorted_keys = sorted(history.keys(), key=lambda k: int(k))
    history = {k: history[k] for k in sorted_keys[-2000:]}

with open(history_file, 'w') as f:
    json.dump(history, f)
" "$HISTORY_FILE" "$SEND_TIMESTAMP" "$MESSAGE" "$QUOTE_TIMESTAMP" 2>/dev/null || true
fi
