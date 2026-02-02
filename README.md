# Brave Core Bot

An autonomous coding agent for working on software projects. This bot reads Product Requirements Documents (PRDs), executes user stories, runs tests, and commits changes automatically.

## Overview

The bot operates in an iterative loop with a state machine workflow:

1. Reads PRD from `prd.json`
2. Picks the next story using smart priority (reviewers first!):
   - **URGENT**: Pushed PRs where reviewer responded (respond immediately)
   - **HIGH**: Pushed PRs where bot responded (check for new reviews/merge)
   - **MEDIUM**: Committed PRs (create PR)
   - **NORMAL**: Start new development work
3. Executes based on current status:
   - **pending**: Implement, test, and commit → `committed`
   - **committed**: Push branch and create PR → `pushed` (lastActivityBy: "bot")
   - **pushed**: Check merge readiness FIRST, then:
     - If mergeable: Merge → `merged` ✅
     - If reviewer commented: Implement feedback, push → (lastActivityBy: "bot")
     - If waiting: Skip to next story (will check again next iteration)
4. Updates progress in `progress.txt`
5. Repeats until all stories have `status: "merged"`

**Story Lifecycle:**
```
     pending
        ↓
    (implement + test)
        ↓
    committed
        ↓
    (push + create PR)
        ↓
     pushed ◄─────────┐
    ╱   │   ╲         │
   ╱    │    ╲        │
merge  wait  review   │
  │     │     ↓       │
  │     │   (implement + test)
  │     │     ↓       │
  │     │   (commit + push)
  │     │     └───────┘
  ↓     │
merged  └─► (check again next iteration)
```

**Key Points:**
- Initial development: pending → (implement+test) → committed
- Review response: pushed → (implement+test) → (commit+push) → pushed
- **Same quality gates apply** - ALL tests must pass whether initial development or responding to reviews

**Anti-Stuck Guarantee:** Every `pushed` PR is checked for merge readiness on EVERY iteration, even when `lastActivityBy: "bot"`. This ensures approved PRs never get stuck.

**Smart Waiting:** The bot tracks `lastActivityBy` to avoid spamming PRs while ensuring progress. See [STATE-MACHINE.md](STATE-MACHINE.md) for detailed flow.

## Prerequisites

- **Claude Code CLI** installed and configured
- **jq** for JSON parsing: `sudo apt install jq` (Ubuntu/Debian) or `brew install jq` (macOS)
- **Git** configured with your credentials
- **Claude API key** configured for Claude Code CLI
- Access to brave/brave-browser repository

## Setup

### 1. Clone This Repository

Clone this repository at the root of your brave-browser checkout, alongside the `src` directory (2 levels above `src/brave`):

```
brave-browser/
├── src/
│   └── brave/              # Target git repository
└── brave-core-bot/         # This bot (clone here)
    ├── run.sh
    ├── prd.json
    └── ...
```

**Clone command:**
```bash
cd /path/to/brave-browser
git clone https://github.com/your-org/brave-core-bot.git
```

### 2. Configure Git

The bot needs git credentials to commit changes. Configure git in `src/brave`:

```bash
cd brave-browser/src/brave

# Set your bot's git identity
git config user.name "netzenbot"
git config user.email "netzenbot@brave.com"
```

**Important:** These settings are repository-specific (stored in `.git/config`), not global.

### 3. Create Configuration Files

The repository includes example templates that you need to copy and customize:

```bash
cd brave-core-bot

# Copy example files to create your configuration
cp prd.example.json prd.json
cp run-state.example.json run-state.json
cp progress.example.txt progress.txt

# Edit prd.json to set your working directory
# Replace "/absolute/path/to/your/working/directory" with your actual path
# Example: "/home/username/projects/brave-browser/src/brave"
```

**Important:** These files contain user-specific paths and runtime state, so they're gitignored. Never commit your actual `prd.json`, `progress.txt`, or `run-state.json` files.

### 4. Run Setup Script

The setup script installs the pre-commit hook and Claude Code skills:

```bash
cd brave-core-bot
./setup.sh
```

This will:
- Install the pre-commit hook to your target repository
- Install Claude Code skills for PRD generation and management
- Verify git configuration
- Display next steps

**Installed Skills:**
- `/brave_core_prd` - Generate Product Requirements Documents
- `/brave_core_prd_json` - Convert PRDs to prd.json format

### 5. Create Your PRD

You can create a PRD in two ways:

**Option A: Use the `/brave_core_prd` skill** (recommended for new features)
```bash
claude
> /brave_core_prd
```
Follow the prompts to generate a structured PRD, then use `/brave_core_prd_json` to convert it to `prd.json`.

**Option B: Manually edit `prd.json`**

Edit `prd.json` to define:
- **config.workingDirectory**: Path to your git repository (absolute or relative to parent directory)
- **userStories**: List of tasks with acceptance criteria

Example:
```json
{
  "config": {
    "workingDirectory": "src/brave"
  },
  "userStories": [
    {
      "id": "STORY-1",
      "title": "Fix authentication test",
      "priority": 1,
      "status": "pending",
      "branchName": null,
      "prNumber": null,
      "prUrl": null,
      "lastActivityBy": null,
      "acceptanceCriteria": [
        "npm run test -- auth_tests from src/brave"
      ]
    }
  ]
}
```

**Status field values:**
- `"pending"` - Ready for development
- `"committed"` - Needs PR creation
- `"pushed"` - PR created, in review
- `"merged"` - Complete

**lastActivityBy field values:**
- `null` - Not yet public or fresh PR
- `"bot"` - Bot responded last, waiting for reviewer
- `"reviewer"` - Reviewer responded last, bot should act

## Workflow

### Creating a PRD

Use the `/brave_core_prd` skill in Claude Code to generate a structured PRD:

```bash
claude
> /brave_core_prd [describe your feature]
```

This will:
1. Ask clarifying questions about your feature
2. Generate a structured PRD with user stories
3. Save it to the `tasks/` directory

### Converting to prd.json

Once you have a PRD, convert it to the bot's JSON format:

```bash
claude
> convert this prd to prd.json format
```

Or manually create/edit `prd.json` following the structure shown in the Configuration section.

## Usage

### Run the Bot

```bash
cd brave-core-bot
./run.sh
```

**Options:**
- `[number]`: Maximum iterations (default: 10)

**Examples:**
```bash
# Run with default settings (10 iterations)
./run.sh

# Run with 20 iterations
./run.sh 20
```

### Monitor Progress

The bot logs all progress to `progress.txt`:
```bash
tail -f progress.txt
```

### Stop the Bot

Press `Ctrl+C` to stop. The bot will attempt to switch back to the master branch before exiting.

## Configuration Files

### prd.json

Product Requirements Document defining user stories and acceptance criteria.

**Key Fields:**
- `config.workingDirectory`: Git repository path (typically `src/brave`)
- `userStories[].id`: Unique story identifier
- `userStories[].priority`: Execution order (1 = highest)
- `userStories[].status`: Story state - "pending" | "committed" | "pushed" | "merged"
- `userStories[].branchName`: Git branch name (set when work starts, reused across iterations)
- `userStories[].prNumber`: PR number (set when PR created)
- `userStories[].prUrl`: PR URL (set when PR created)
- `userStories[].lastActivityBy`: Who acted last - "bot" | "reviewer" | null
- `userStories[].acceptanceCriteria`: Test commands that must pass

### CLAUDE.md

Instructions for the Claude AI agent. Defines:
- Task workflow and rules
- Testing requirements (never skip tests)
- Git workflow and branch management
- Problem-solving approach
- Security guidelines
- Quality standards

### progress.txt

Log of completed iterations, including:
- What was implemented
- Files changed
- Test results
- Learnings and patterns

## Git Workflow

### Branch Management

Each user story should have its own branch:

```bash
cd /path/to/your/repo
git checkout master
git pull origin master
git checkout -b fix-specific-issue
```

The bot creates branches automatically based on `prd.json`.

### Pre-commit Hook

The included pre-commit hook blocks dependency file changes for the `netzenbot` account:

**Blocked Files:**
- package.json, package-lock.json, npm-shrinkwrap.json
- yarn.lock, pnpm-lock.yaml
- DEPS (Chromium)
- Cargo.toml, Cargo.lock
- go.mod, go.sum
- Gemfile.lock, poetry.lock, Pipfile.lock, composer.lock

**Purpose:** Prevents bots from introducing external dependencies without review.

### Commit Format

The bot uses conventional commit messages:
```
feat: [Story ID] - [Story Title]

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

## Testing Philosophy

**Critical Rule:** All acceptance criteria tests MUST run and pass before marking a story as complete.

The bot will:
- Run ALL tests specified in acceptance criteria
- Use background execution for long-running tests
- Never skip tests regardless of duration
- Only mark `passes: true` when tests actually pass
- Never use workarounds or arbitrary waits

## Archiving

When the branch changes between runs, the bot automatically archives the previous run:

```
brave-core-bot/archive/
  └── 2026-01-30-old-branch/
      ├── prd.json
      └── progress.txt
```

## Testing

Run the automated test suite to verify everything is set up correctly:

```bash
cd brave-core-bot
./tests/test-suite.sh
```

The test suite validates:
- ✅ GitHub API integration and org membership checks
- ✅ File structure and permissions
- ✅ Filtering scripts and security measures
- ✅ Pre-commit hook functionality
- ✅ Configuration file validity

**Exit codes:** `0` = all tests passed, `1` = failures detected

See `tests/README.md` for detailed test documentation.

## Troubleshooting

### "Git user not configured"

Run setup again or manually configure git:
```bash
cd brave-browser/src/brave
git config user.name "netzenbot"
git config user.email "netzenbot@brave.com"
```

### "Pre-commit hook blocks my commit"

If you're the `netzenbot` account and trying to modify dependencies:
- This is intentional - bots should not update dependencies
- Use existing libraries in the codebase
- If truly necessary, use a different git account

### "Tests are taking too long"

This is expected. The bot uses:
- `run_in_background: true` for long operations
- High timeout values (1-2 hours)
- The TaskOutput tool to monitor progress

### "Build failures after sync"

If `npm run build` fails, the bot will automatically run:
```bash
git fetch
git rebase origin/master
npm run sync -- --no-history
```

## Project Structure

```
brave-core-bot/
├── README.md              # This file
├── STATE-MACHINE.md       # Detailed state machine documentation
├── SECURITY.md            # Security guidelines and best practices
├── setup.sh               # Setup script (installs hook, skills, checks config)
├── run.sh                 # Main entry point
├── CLAUDE.md              # Claude agent instructions
├── prd.json               # Product requirements (user stories)
├── progress.txt           # Progress log
├── .last-branch           # Tracks branch changes
├── .gitignore             # Git ignore rules
├── hooks/
│   └── pre-commit         # Git pre-commit hook (blocks dependency updates)
├── scripts/
│   ├── fetch-issue.sh     # Fetch and display filtered GitHub issues
│   ├── filter-issue-json.sh  # Filter GitHub issues to org members only
│   └── filter-pr-reviews.sh  # Filter PR reviews to org members only
├── skills/
│   ├── brave_core_prd.md          # PRD generation skill
│   └── brave_core_prd_json.md     # PRD to JSON converter skill
└── tests/
    ├── test-suite.sh      # Automated test suite
    └── README.md          # Test documentation
```

## Security

### Prompt Injection Protection

The bot includes protection against prompt injection attacks from external GitHub users:

**Filter GitHub Issues:**
```bash
# Fetch and filter issue content (only includes Brave org members)
./scripts/filter-issue-json.sh 12345 markdown

# JSON output for programmatic use
./scripts/filter-issue-json.sh 12345 json
```

**How it works:**
- Fetches issue data from GitHub
- Checks comment authors against Brave org membership
- Filters out content from external users
- Caches org membership for performance (1-hour TTL)

**Why:** External users can post comments on public issues attempting to manipulate bot behavior, bypass security policies, or introduce malicious code.

See `SECURITY.md` for complete security guidelines.

### Other Security Notes

1. **Dependency Restrictions:** The pre-commit hook prevents netzenbot from updating dependencies
2. **Bot Permissions:** Uses `--dangerously-skip-permissions` for autonomous operation
3. **Review Commits:** Always review bot commits before pushing to remote
4. **API Keys:** Ensure Claude API keys are properly configured
5. **Dedicated Account:** Use the netzenbot account with restricted permissions

## Contributing

When adding new patterns or learnings:
1. Update `CLAUDE.md` for agent-level patterns
2. Update `progress.txt` for codebase-specific patterns
3. Keep the README focused on setup and usage

## License

[Your License Here]

## Support

For issues or questions:
- Check `progress.txt` for detailed logs
- Review `CLAUDE.md` for agent behavior
- Verify git configuration with `./setup.sh`
