---
name: prd-clean
description: "Archive merged and invalid stories from prd.json to prd.archived.json, keeping only active work in the main PRD. Triggers on: clean prd, archive merged stories, clean up prd, move merged stories."
---

# PRD Clean - Archive Completed Stories

Automatically move merged and invalid stories from prd.json to prd.archived.json, keeping the main PRD focused on active work.

---

## The Job

1. Read the current PRD (`./prd.json`)
2. Identify stories with status "merged" or "invalid"
3. Move those stories to `prd.archived.json` (creating or merging with existing file)
4. Update `prd.json` to contain only active stories (pending, committed, pushed)
5. Provide a recap of what was archived

**Important:** This skill is specifically for the Brave Core Bot PRD format. It preserves all story data in prd.archived.json for historical reference.

---

## How It Works

The helper script `.claude/skills/prd-clean/clean_prd.py` handles the archival process:

```bash
.claude/skills/prd-clean/clean_prd.py ./prd.json > /tmp/prd_cleaned.json && \
  mv /tmp/prd_cleaned.json ./prd.json
```

### What the script does:

- Reads prd.json and identifies merged/invalid stories
- Reads existing prd.archived.json (if it exists) to merge archived stories
- Updates or adds archived stories (avoiding duplicates by ID)
- Writes all archived stories to prd.archived.json
- Outputs updated prd.json with only active stories to stdout
- Provides summary to stderr showing what was archived

---

## Usage

Run the script to clean the PRD:

```bash
.claude/skills/prd-clean/clean_prd.py ./prd.json > /tmp/prd_cleaned.json && \
  mv /tmp/prd_cleaned.json ./prd.json
```

The script will:
- Create or update `./prd.archived.json` with archived stories
- Output the cleaned PRD to stdout (redirected to temp file, then moved)
- Print summary information to stderr

---

## Provide Recap

Generate a comprehensive recap showing:

1. **Archived Stories Summary**:
   - Count of merged stories archived
   - Count of invalid stories archived
   - Total stories now in prd.archived.json

2. **Active Stories Remaining**:
   - Count by status (pending, committed, pushed)
   - Total active stories

3. **Archived Story List**:
   - ID, title, and status for each archived story

---

## Example Output Format

```markdown
# PRD Cleaning Recap

## Summary
Archived 8 completed stories from prd.json to prd.archived.json.

## Archived Stories (8 total)

### Merged (6 stories)
- US-001: Fix test: SolanaProviderTest.AccountChangedEventAndReload
- US-002: Fix test: BraveWalletRpcRequestTest.ChainChanged
- US-003: Fix test: WebDiscoveryBrowserTest.TestWebDiscoveryInfobar
- US-004: Fix test: AdBlockServiceTest.GetDATFileData
- US-005: Fix test: BraveWalletProviderTest.MultipleConnections
- US-006: Fix test: RewardsPageBrowserTest.TipPanel

### Invalid (2 stories)
- US-012: Fix test: InvalidTestCase (marked invalid due to upstream fix)
- US-018: Fix test: DuplicateTestCase (marked invalid - duplicate)

## Active Stories Remaining (7 total)

### Pending (5 stories)
- US-007: Fix test: BraveSearchTestEnabled.DefaultAPIVisibleKnownHost
- US-008: Fix test: RewardsPanelBrowserTest.OpenPanel
- US-009: Fix test: BraveTorTest.TorProfile
- US-010: Fix test: IpfsServiceTest.ImportFileOnService
- US-011: Fix test: BraveSyncServiceTest.OnSetupSyncHaveValidCode

### Pushed (1 story)
- US-013: Fix test: PlaylistBrowserTest.AddItemsFromPage

### Committed (1 story)
- US-014: Fix test: BraveFederatedServiceTest.SetSchedule

## PRD Statistics
- Stories archived: 8 (6 merged, 2 invalid)
- Stories in prd.archived.json: 8
- Active stories: 7 (5 pending, 1 pushed, 1 committed)
```

---

## Important Notes

- All archived stories are preserved in prd.archived.json with full data
- If prd.archived.json already exists, new archived stories are merged in
- Duplicate stories (by ID) are updated with latest data
- Only stories with status "merged" or "invalid" are archived
- Active stories (pending, committed, pushed, skipped) remain in prd.json
- The prd.archived.json file is added to .gitignore (not version controlled)

---

## When to Use This

Use this skill when:
- prd.json has accumulated many merged stories and is getting large
- You want to focus on active work in the main PRD
- You need to archive completed work for historical reference
- You're cleaning up before starting a new batch of stories

This is particularly useful for long-running projects where the PRD accumulates many completed stories over time.

---

## Error Handling

- If `./prd.json` doesn't exist, report error and exit
- If prd.json is invalid JSON, report error and exit
- If prd.archived.json exists but is invalid JSON, start with empty archive and warn user
- If no stories need archiving, report that and do nothing
