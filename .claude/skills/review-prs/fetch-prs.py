#!/usr/bin/env python3
"""Fetch and filter brave/brave-core PRs for review.

Handles all PR fetching, filtering, and cache checking in one script
so the LLM doesn't burn tokens on this logic.

Usage: fetch-prs.py [days|page<N>] [open|closed|all]

Examples:
  fetch-prs.py              # Default: 5 days, open PRs
  fetch-prs.py 3            # Last 3 days, open PRs
  fetch-prs.py page2        # Page 2 (PRs 21-40), open PRs
  fetch-prs.py 7 closed     # Last 7 days, closed PRs
  fetch-prs.py page1 all    # Page 1, all states

Output: JSON with "prs" array and "summary" stats.
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta, timezone


CACHE_PATH = ".ignore/review-prs-cache.json"
SKIP_PREFIXES = ["CI run for", "Backport", "Update l10n"]
SKIP_CONTAINS = ["uplift to", "Just to test CI"]


def parse_args():
    mode = "days"
    days = 5
    page = None
    state = "open"

    for arg in sys.argv[1:]:
        if arg.startswith("page"):
            mode = "page"
            page = int(arg[4:])
        elif arg in ("open", "closed", "all"):
            state = arg
        else:
            try:
                days = int(arg)
            except ValueError:
                pass

    return mode, days, page, state


def fetch_prs(mode, days, page, state):
    fields = "number,title,createdAt,author,isDraft,headRefOid"
    base_cmd = [
        "gh", "pr", "list", "--repo", "brave/brave-core",
        "--state", state, "--json", fields,
    ]

    if mode == "page":
        limit = page * 20
        result = subprocess.run(
            base_cmd + ["--limit", str(limit)],
            capture_output=True, text=True, check=True,
        )
        prs = json.loads(result.stdout)
        start = (page - 1) * 20
        return prs[start:start + 20]
    else:
        result = subprocess.run(
            base_cmd + ["--limit", "200"],
            capture_output=True, text=True, check=True,
        )
        return json.loads(result.stdout)


def load_cache():
    try:
        with open(CACHE_PATH) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def should_skip_title(title):
    for prefix in SKIP_PREFIXES:
        if title.startswith(prefix):
            return True
    for pattern in SKIP_CONTAINS:
        if pattern in title:
            return True
    return False


def filter_prs(prs, mode, days, cache):
    cutoff = None
    if mode == "days":
        cutoff = datetime.now(timezone.utc) - timedelta(days=days)

    to_review = []
    skipped_filtered = 0
    skipped_cached = 0

    for pr in prs:
        if pr.get("isDraft"):
            skipped_filtered += 1
            continue

        if should_skip_title(pr.get("title", "")):
            skipped_filtered += 1
            continue

        if cutoff and mode == "days":
            created = datetime.fromisoformat(
                pr["createdAt"].replace("Z", "+00:00")
            )
            if created < cutoff:
                skipped_filtered += 1
                continue

        pr_num = str(pr["number"])
        head_sha = pr.get("headRefOid", "")
        if cache.get(pr_num) == head_sha:
            skipped_cached += 1
            continue

        to_review.append(pr)

    return to_review, skipped_filtered, skipped_cached


def main():
    mode, days, page, state = parse_args()
    prs = fetch_prs(mode, days, page, state)
    cache = load_cache()
    to_review, skipped_filtered, skipped_cached = filter_prs(
        prs, mode, days, cache
    )

    output = {
        "prs": [
            {
                "number": pr["number"],
                "title": pr["title"],
                "headRefOid": pr["headRefOid"],
                "author": pr.get("author", {}).get("login", "unknown"),
            }
            for pr in to_review
        ],
        "summary": {
            "total_fetched": len(prs),
            "to_review": len(to_review),
            "skipped_filtered": skipped_filtered,
            "skipped_cached": skipped_cached,
        },
    }

    json.dump(output, sys.stdout, indent=2)
    print()


if __name__ == "__main__":
    main()
