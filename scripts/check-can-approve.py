#!/usr/bin/env python3
"""
Gate check before the bot approves a PR.

Returns exit code 0 and prints JSON with "can_approve": true ONLY when:
  1. The bot has at least one review thread on the PR
  2. ALL bot threads are resolved (zero unresolved)
  3. The bot has not already approved at the current HEAD SHA

If any condition fails, returns exit code 1 and prints the reason.
This script is the SINGLE SOURCE OF TRUTH for approval decisions —
the LLM must not approve without a passing exit code from this script.

Usage:
    python3 check-can-approve.py <pr-number> <bot-username>
"""

import argparse
import json
import subprocess
import sys


def gh_api(endpoint, method="GET", input_data=None):
    """Call a GitHub API endpoint via gh CLI."""
    cmd = ["gh", "api", endpoint]
    if method != "GET":
        cmd += ["--method", method]
    if input_data:
        cmd += ["--input", "-"]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=30,
        input=json.dumps(input_data) if input_data else None,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def gh_graphql(query, variables):
    """Call the GitHub GraphQL API via gh CLI."""
    cmd = ["gh", "api", "graphql", "-f", f"query={query}"]
    for key, value in variables.items():
        if isinstance(value, int):
            cmd += ["-F", f"{key}={value}"]
        else:
            cmd += ["-f", f"{key}={value}"]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def fetch_bot_thread_status(pr_number, bot_username):
    """Fetch all review threads and return bot thread resolution stats."""
    query = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          headRefOid
          reviewThreads(first: 100) {
            nodes {
              id
              isResolved
              comments(first: 1) {
                nodes {
                  author { login }
                }
              }
            }
          }
        }
      }
    }
    """
    data = gh_graphql(query, {
        "owner": "brave",
        "name": "brave-core",
        "number": pr_number,
    })
    if not data:
        return None, None, None

    try:
        pr = data["data"]["repository"]["pullRequest"]
        head_sha = pr["headRefOid"]
        threads = pr["reviewThreads"]["nodes"]
    except (KeyError, TypeError):
        return None, None, None

    total = 0
    unresolved = 0
    unresolved_details = []
    for thread in threads:
        first_comments = thread.get("comments", {}).get("nodes", [])
        if not first_comments:
            continue
        author = (first_comments[0].get("author") or {}).get("login", "")
        if author == bot_username:
            total += 1
            if not thread.get("isResolved", False):
                unresolved += 1
                unresolved_details.append(thread["id"])

    return head_sha, {
        "total_bot_threads": total,
        "unresolved_bot_threads": unresolved,
        "unresolved_thread_ids": unresolved_details,
    }, threads


def check_already_approved(pr_number, bot_username, head_sha):
    """Check if the bot already approved at the current HEAD SHA."""
    reviews = gh_api(f"repos/brave/brave-core/pulls/{pr_number}/reviews")
    if not reviews:
        return False
    for review in reviews:
        if (review.get("user", {}).get("login") == bot_username
                and review.get("state") == "APPROVED"
                and review.get("commit_id") == head_sha):
            return True
    return False


def main():
    parser = argparse.ArgumentParser(
        description="Gate check: can the bot approve this PR?"
    )
    parser.add_argument("pr_number", type=int, help="PR number")
    parser.add_argument("bot_username", help="Bot's GitHub username")
    args = parser.parse_args()

    # Fetch thread status
    head_sha, thread_info, _ = fetch_bot_thread_status(
        args.pr_number, args.bot_username
    )
    if head_sha is None or thread_info is None:
        result = {
            "can_approve": False,
            "reason": "Failed to fetch PR data from GitHub API",
        }
        print(json.dumps(result, indent=2))
        sys.exit(1)

    # Check 1: Bot must have at least one thread
    if thread_info["total_bot_threads"] == 0:
        result = {
            "can_approve": False,
            "reason": "Bot has no review threads on this PR — nothing to settle",
            **thread_info,
            "head_sha": head_sha,
        }
        print(json.dumps(result, indent=2))
        sys.exit(1)

    # Check 2: All bot threads must be resolved
    if thread_info["unresolved_bot_threads"] > 0:
        result = {
            "can_approve": False,
            "reason": (
                f"{thread_info['unresolved_bot_threads']} of "
                f"{thread_info['total_bot_threads']} bot threads are still "
                f"unresolved"
            ),
            **thread_info,
            "head_sha": head_sha,
        }
        print(json.dumps(result, indent=2))
        sys.exit(1)

    # Check 3: Bot must not have already approved this SHA
    if check_already_approved(args.pr_number, args.bot_username, head_sha):
        result = {
            "can_approve": False,
            "reason": "Bot already approved at this SHA",
            **thread_info,
            "head_sha": head_sha,
        }
        print(json.dumps(result, indent=2))
        sys.exit(1)

    # All checks pass
    result = {
        "can_approve": True,
        "reason": (
            f"All {thread_info['total_bot_threads']} bot threads resolved"
        ),
        **thread_info,
        "head_sha": head_sha,
    }
    print(json.dumps(result, indent=2))
    sys.exit(0)


if __name__ == "__main__":
    main()
