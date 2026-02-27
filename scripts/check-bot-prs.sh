#!/bin/bash
# Gate script for learnable-pattern-search cron job.
# Exits 0 if the bot user has merged PRs reviewed in the last 2 days.
# Exits 1 if no recent reviewed PRs found (nothing to learn from).
#
# Usage in cron: ./scripts/check-bot-prs.sh && claude -p '/learnable-pattern-search ...' ...

set -euo pipefail

BOT_USERNAME="${1:-netzenbot}"
LOOKBACK_DAYS="${2:-2}"

CUTOFF_DATE=$(date -u -v-${LOOKBACK_DAYS}d +%Y-%m-%d 2>/dev/null || date -u -d "$LOOKBACK_DAYS days ago" +%Y-%m-%d)

PR_COUNT=$(gh search prs --repo brave/brave-core --reviewed-by "$BOT_USERNAME" --state merged --sort updated --limit 1 --json number -- "updated:>=$CUTOFF_DATE" 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

if [ "$PR_COUNT" = "0" ]; then
  echo "No merged PRs reviewed by $BOT_USERNAME since $CUTOFF_DATE — skipping learnable-pattern-search."
  exit 1
fi

echo "Found recent reviewed PRs — proceeding with learnable-pattern-search."
exit 0
