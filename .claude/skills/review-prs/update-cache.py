#!/usr/bin/env python3
"""Update the review-prs cache with a PR's HEAD SHA after review."""

import json
import os
import sys

if len(sys.argv) != 3:
    print(f"Usage: {sys.argv[0]} <pr_number> <head_ref_oid>", file=sys.stderr)
    sys.exit(1)

pr_number = sys.argv[1]
head_ref_oid = sys.argv[2]

cache_path = ".ignore/review-prs-cache.json"

try:
    with open(cache_path) as f:
        cache = json.load(f)
except (FileNotFoundError, json.JSONDecodeError):
    cache = {}
    os.makedirs(os.path.dirname(cache_path), exist_ok=True)

cache[pr_number] = head_ref_oid

with open(cache_path, "w") as f:
    json.dump(cache, f, indent=2)
    f.write("\n")

print(f"Cache updated: PR #{pr_number} -> {head_ref_oid}")
