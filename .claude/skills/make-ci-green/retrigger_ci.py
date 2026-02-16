#!/usr/bin/env python3
"""
Re-run failed CI jobs for a brave/brave-core PR.

Queries GitHub for failing checks, determines the failure stage via Jenkins API,
and triggers rebuilds with WIPE_WORKSPACE for build/infra failures or normal
re-runs for test/storybook failures.

Usage:
    python3 retrigger_ci.py <pr-number> [--dry-run] [--format json|markdown]
"""

import argparse
import base64
import json
import os
import subprocess
import sys
import urllib.error
import urllib.request
from urllib.parse import urlparse

JENKINS_BASE_URL = os.environ.get("JENKINS_BASE_URL", "").rstrip("/")
JENKINS_USER = os.environ.get("JENKINS_USER", "")

# Stage name keywords that indicate pre-test infrastructure failures.
# These warrant WIPE_WORKSPACE to clear potentially corrupted build state.
WIPE_WORKSPACE_KEYWORDS = {
    "init",
    "checkout",
    "install",
    "config",
    "build",
    "compile",
    "setup",
    "sync",
    "gclient",
    "source",
    "deps",
    "fetch",
    "configure",
    "bootstrap",
    "prepare",
    "environment",
}


def get_jenkins_auth():
    """Get Jenkins authentication credentials from environment.

    Returns:
        tuple of (user, token) or exits with error.
    """
    missing = []
    if not JENKINS_BASE_URL:
        missing.append("JENKINS_BASE_URL")
    if not JENKINS_USER:
        missing.append("JENKINS_USER")
    token = os.environ.get("JENKINS_TOKEN")
    if not token:
        missing.append("JENKINS_TOKEN")
    if missing:
        print(
            f"Error: Required environment variable(s) not set: {', '.join(missing)}\n"
            "Set them in your .envrc:\n"
            "  export JENKINS_BASE_URL=<value>\n"
            "  export JENKINS_USER=<value>\n"
            "  export JENKINS_TOKEN=<value>",
            file=sys.stderr,
        )
        sys.exit(1)
    return JENKINS_USER, token


def make_auth_header(user, token):
    """Create Basic Auth header value."""
    credentials = base64.b64encode(f"{user}:{token}".encode()).decode()
    return f"Basic {credentials}"


def get_crumb(auth_header):
    """Fetch Jenkins CSRF crumb for POST requests.

    Returns:
        dict with crumb header name and value, or None if crumbs are disabled.
    """
    url = f"{JENKINS_BASE_URL}/crumbIssuer/api/json"
    req = urllib.request.Request(
        url,
        headers={"Authorization": auth_header},
    )
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            data = json.loads(resp.read())
            return {data["crumbRequestField"]: data["crumb"]}
    except (urllib.error.HTTPError, urllib.error.URLError, KeyError):
        # Crumb issuer may be disabled; proceed without it
        return None


def get_failing_checks(pr_number):
    """Query GitHub for PR check statuses.

    Returns:
        list of dicts with keys: name, state, link, is_jenkins
    """
    result = subprocess.run(
        [
            "gh", "pr", "checks", str(pr_number),
            "--repo", "brave/brave-core",
            "--json", "name,state,link",
        ],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"Error: Failed to get PR checks: {result.stderr}", file=sys.stderr)
        sys.exit(2)

    checks = json.loads(result.stdout)
    results = []
    for check in checks:
        is_jenkins = "ci.brave.com" in check.get("link", "")
        results.append({
            "name": check["name"],
            "state": check["state"],
            "link": check.get("link", ""),
            "is_jenkins": is_jenkins,
        })
    return results


def parse_jenkins_url(link):
    """Parse a Jenkins build URL into components.

    Example input: https://ci.brave.com/job/brave-core-build-pr-linux-x64/job/PR-33936/2/
    Returns: ("brave-core-build-pr-linux-x64", "PR-33936", "2")
    """
    parsed = urlparse(link)
    path = parsed.path.rstrip("/")
    parts = path.split("/")

    # Expected: /job/<job-name>/job/<branch>/<build-number>
    # parts: ['', 'job', 'brave-core-build-pr-linux-x64', 'job', 'PR-33936', '2']
    job_name = None
    branch = None
    build_number = None

    i = 0
    while i < len(parts):
        if parts[i] == "job" and i + 1 < len(parts):
            if job_name is None:
                job_name = parts[i + 1]
            else:
                branch = parts[i + 1]
            i += 2
        else:
            # The last segment after job/branch is the build number
            if branch is not None and parts[i]:
                build_number = parts[i]
            i += 1

    return job_name, branch, build_number


def get_failed_stage(job, branch, build, auth_header):
    """Query Jenkins API for the failed pipeline stage.

    Returns:
        The name of the first failed stage, or None if not determinable.
    """
    url = (
        f"{JENKINS_BASE_URL}/job/{job}/job/{branch}/{build}/wfapi/describe"
    )
    req = urllib.request.Request(
        url,
        headers={"Authorization": auth_header},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        print(
            f"  Warning: Jenkins API returned HTTP {e.code} for {job}/{branch}/{build}",
            file=sys.stderr,
        )
        return None
    except urllib.error.URLError as e:
        print(
            f"  Warning: Could not reach Jenkins API: {e.reason}",
            file=sys.stderr,
        )
        return None

    # wfapi/describe returns {"stages": [{"name": "...", "status": "..."}]}
    stages = data.get("stages", [])
    for stage in stages:
        if stage.get("status") in ("FAILED", "ABORTED"):
            return stage.get("name")

    return None


def decide_action(stage_name):
    """Decide whether to use WIPE_WORKSPACE based on the failed stage.

    Returns:
        tuple of (wipe: bool, reason: str)
    """
    if stage_name is None:
        return False, "Could not determine failed stage; defaulting to normal re-run"

    stage_lower = stage_name.lower()

    # Check if the stage name contains any WIPE_WORKSPACE keywords
    for keyword in WIPE_WORKSPACE_KEYWORDS:
        if keyword in stage_lower:
            return True, f"Pre-test stage failure: \"{stage_name}\" -> WIPE_WORKSPACE"

    return False, f"Test/post-build stage failure: \"{stage_name}\" -> normal re-run"


def trigger_build(job, branch, wipe, auth_header, crumb):
    """Trigger a Jenkins build.

    Returns:
        True on success, False on failure.
    """
    if wipe:
        url = (
            f"{JENKINS_BASE_URL}/job/{job}/job/{branch}"
            f"/buildWithParameters?WIPE_WORKSPACE=true"
        )
    else:
        url = (
            f"{JENKINS_BASE_URL}/job/{job}/job/{branch}/buildWithParameters"
        )

    headers = {
        "Authorization": auth_header,
        "Content-Type": "application/x-www-form-urlencoded",
    }
    if crumb:
        headers.update(crumb)

    req = urllib.request.Request(url, data=b"", headers=headers, method="POST")

    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            # Jenkins returns 201 (Created) or 302 (redirect) on success
            return True
    except urllib.error.HTTPError as e:
        # 201 may come as an "error" in some urllib versions
        if e.code in (201, 302):
            return True
        print(
            f"  Error: Jenkins returned HTTP {e.code} when triggering "
            f"{job}/{branch}: {e.reason}",
            file=sys.stderr,
        )
        return False
    except urllib.error.URLError as e:
        print(
            f"  Error: Could not reach Jenkins to trigger build: {e.reason}",
            file=sys.stderr,
        )
        return False


def format_markdown(results, pr_number, dry_run):
    """Format results as human-readable markdown."""
    lines = []

    failing = [r for r in results if r["state"] == "FAILURE" and r["is_jenkins"]]
    non_jenkins_failing = [r for r in results if r["state"] == "FAILURE" and not r["is_jenkins"]]
    pending = [r for r in results if r["state"] == "PENDING" and r["is_jenkins"]]

    if not failing:
        lines.append(f"No failing Jenkins CI checks found for PR {pr_number}.")
        if non_jenkins_failing:
            lines.append("")
            lines.append("Non-Jenkins failures (not handled by this tool):")
            for r in non_jenkins_failing:
                lines.append(f"  - {r['name']}")
        return "\n".join(lines)

    action_word = "Would retrigger" if dry_run else "Retriggered"
    lines.append(f"PR {pr_number}: {len(failing)} failing Jenkins check(s)\n")

    for r in failing:
        status_icon = "OK" if r.get("triggered") else ("DRY-RUN" if dry_run else "FAILED")
        action = "WIPE_WORKSPACE" if r.get("wipe") else "normal"
        lines.append(f"  [{status_icon}] {r['name']}")
        lines.append(f"       Stage: {r.get('failed_stage', 'unknown')}")
        lines.append(f"       Action: {action}")
        lines.append(f"       Reason: {r.get('reason', '')}")
        lines.append(f"       URL: {r.get('link', '')}")
        lines.append("")

    if non_jenkins_failing:
        lines.append("Non-Jenkins failures (skipped):")
        for r in non_jenkins_failing:
            lines.append(f"  - {r['name']}")
        lines.append("")

    if pending:
        lines.append("Still pending:")
        for r in pending:
            lines.append(f"  - {r['name']}")

    return "\n".join(lines)


def format_json(results, pr_number, dry_run):
    """Format results as JSON."""
    failing = [r for r in results if r["state"] == "FAILURE" and r["is_jenkins"]]
    non_jenkins_failing = [r for r in results if r["state"] == "FAILURE" and not r["is_jenkins"]]
    pending = [r for r in results if r["state"] == "PENDING" and r["is_jenkins"]]

    output = {
        "pr_number": pr_number,
        "dry_run": dry_run,
        "failing_jenkins_checks": [
            {
                "name": r["name"],
                "link": r.get("link", ""),
                "failed_stage": r.get("failed_stage"),
                "wipe_workspace": r.get("wipe", False),
                "reason": r.get("reason", ""),
                "triggered": r.get("triggered", False),
            }
            for r in failing
        ],
        "non_jenkins_failures": [r["name"] for r in non_jenkins_failing],
        "pending": [r["name"] for r in pending],
    }
    return json.dumps(output, indent=2)


def main():
    parser = argparse.ArgumentParser(
        description="Re-run failed CI jobs for a brave/brave-core PR."
    )
    parser.add_argument("pr_number", type=int, help="PR number in brave/brave-core")
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Analyze failures without triggering rebuilds",
    )
    parser.add_argument(
        "--format",
        choices=["json", "markdown"],
        default="markdown",
        help="Output format (default: markdown)",
    )
    args = parser.parse_args()

    # Validate Jenkins credentials
    user, token = get_jenkins_auth()
    auth_header = make_auth_header(user, token)

    # Get all check statuses
    print(f"Fetching checks for PR {args.pr_number}...", file=sys.stderr)
    checks = get_failing_checks(args.pr_number)

    # Find failing Jenkins checks
    failing_jenkins = [
        c for c in checks
        if c["state"] == "FAILURE" and c["is_jenkins"]
    ]

    if not failing_jenkins:
        # Format and output even for no-failures case
        output = (
            format_json(checks, args.pr_number, args.dry_run)
            if args.format == "json"
            else format_markdown(checks, args.pr_number, args.dry_run)
        )
        print(output)
        sys.exit(3)

    # Analyze each failing check
    crumb = None
    if not args.dry_run:
        print("Fetching Jenkins CSRF crumb...", file=sys.stderr)
        crumb = get_crumb(auth_header)

    for check in failing_jenkins:
        job, branch, build = parse_jenkins_url(check["link"])
        if not job or not branch:
            check["failed_stage"] = None
            check["wipe"] = False
            check["reason"] = f"Could not parse Jenkins URL: {check['link']}"
            check["triggered"] = False
            continue

        print(f"Checking stage info for {check['name']}...", file=sys.stderr)
        failed_stage = get_failed_stage(job, branch, build, auth_header)
        wipe, reason = decide_action(failed_stage)

        check["failed_stage"] = failed_stage
        check["wipe"] = wipe
        check["reason"] = reason

        if args.dry_run:
            check["triggered"] = False
        else:
            print(
                f"Triggering {'WIPE_WORKSPACE ' if wipe else ''}rebuild for "
                f"{check['name']}...",
                file=sys.stderr,
            )
            check["triggered"] = trigger_build(job, branch, wipe, auth_header, crumb)

    # Output results
    output = (
        format_json(checks, args.pr_number, args.dry_run)
        if args.format == "json"
        else format_markdown(checks, args.pr_number, args.dry_run)
    )
    print(output)


if __name__ == "__main__":
    main()
