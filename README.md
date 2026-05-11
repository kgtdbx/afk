# AFK Runners: Ralph & Sandcastle

Two ways to run the Ralph AFK loop. Same interface, different runtimes. An LLM (or human) can follow these instructions to set up either runner from scratch.

## Prerequisites (both runners)

- Docker Desktop installed and running
- `gh` CLI installed and authenticated (`gh auth login`)
- `pnpm install` run in the project root

## Setup: Ralph (custom Docker)

### Step 1: Create auth token file

```bash
claude setup-token
# Copy the output token, then:
echo "your-token-here" > ~/.claude_auth.txt
```

### Step 2: Copy files to their destinations

```bash
cp afk/ralph/afk.sh ralph/afk.sh
cp afk/ralph/Dockerfile.ralph Dockerfile.ralph
```

Note: `afk/ralph/prompt.md` stays where it is — the script reads it directly.

### Step 3: Build the Docker image (auto-builds on first run, or manually)

```bash
# Default git identity (placeholder: "Ralph" / "ralph@afk.dev")
docker build -t ralph-runner -f Dockerfile.ralph .

# With your own git identity (used for Ralph's commits)
docker build -t ralph-runner -f Dockerfile.ralph \
  --build-arg GIT_USER_NAME="Your Name" \
  --build-arg GIT_USER_EMAIL="you@example.com" .
```

### Step 4: Run

```bash
./ralph/afk.sh 5
```

## Setup: Sandcastle

### Step 1: Merge the Sandcastle branch and install dependency

```bash
git fetch upstream with-sandcastle
git merge upstream/with-sandcastle
pnpm install
```

If the merge was already done previously but a codebase reset removed the dependency:
```bash
pnpm add @ai-hero/sandcastle
```

### Step 2: Copy files to their destinations

```bash
cp afk/sandcastle/afk.sh ralph/afk.sh
cp afk/sandcastle/main.ts .sandcastle/main.ts
cp afk/sandcastle/sandcastle-prompt.md .sandcastle/sandcastle-prompt.md
cp afk/sandcastle/Dockerfile .sandcastle/Dockerfile
cp afk/sandcastle/.env.example .sandcastle/.env.example
```

Note: `afk/sandcastle/prompt.md` is copied to `ralph/prompt.md` automatically by `afk.sh` at runtime.

### Step 3: Create `.sandcastle/.env` (skip if it already exists with valid tokens)

```bash
# Check first — .env survives codebase resets since it's gitignored
cat .sandcastle/.env 2>/dev/null || cp .sandcastle/.env.example .sandcastle/.env
```

Then edit `.sandcastle/.env` with real values (if newly created):

| Variable                  | How to get it                                                                                | Purpose                                                  |
| ------------------------- | -------------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token`                                                                         | Authenticates Claude Code with your Max/Pro subscription |
| `GH_TOKEN`                | `gh auth token`                                                                              | Authenticates `gh` CLI inside the container              |
| `GH_REPO`                 | Extract `owner/repo` from `git remote get-url origin` (e.g. `kgtdbx/cohort-003-project-kgt`) | Ensures `gh` targets your fork, not upstream             |

Do NOT commit `.sandcastle/.env` — it contains secrets.

### Step 4: Build the Sandcastle Docker image

```bash
pnpm sandcastle docker build-image
```

### Step 5: Apply any pending DB migrations (if Ralph committed schema changes)

```bash
npx drizzle-kit push
```

This creates tables like `xp_events`, `streak_activities`, etc. in your local SQLite DB. Without this, you'll get `SqliteError: no such table` when running `npm run dev`.

### Step 6: Run

```bash
./ralph/afk.sh 5
```

Watch logs in another terminal:

```bash
tail -f .sandcastle/logs/<branch-name>.log
```

## Where to Run From

Always run from the project root:

```bash
cd /Users/krl/Documents/dev/cohort-003-project-main
./afk/sandcastle/afk.sh 5
```

The scripts use `git remote` and `gh issue list` early on (before resolving paths), so they need to be inside the git repo. Running from the project root guarantees everything works — `git`, `gh`, relative file paths, and Sandcastle's `npx tsx` all resolve correctly.

## Usage (identical for both)

```bash
# Pick from all open GitHub issues (default)
./ralph/afk.sh 5

# Specific issues
./ralph/afk.sh 3 --issue 1 --issue 2

# Plan/PRD files
./ralph/afk.sh 3 --file plans/plan.md --file plans/prd.md

# Mix issues and files (any combo, any order, repeatable)
./ralph/afk.sh 5 --issue 1 --file plans/prd.md --issue 12 --file plans/prd2.md
```

## Directory Structure

```
afk/
├── ralph/                      # Custom Docker container runner
│   ├── afk.sh                  # Entry point
│   ├── prompt.md               # Ralph's instructions (read directly via $SCRIPT_DIR)
│   └── Dockerfile.ralph        # Container image definition
│
└── sandcastle/                 # Sandcastle library runner
    ├── afk.sh                  # Entry point
    ├── prompt.md               # Ralph's instructions (copied to ralph/prompt.md at runtime)
    ├── main.ts                 # Sandcastle config (agent, model, hooks, completion signal)
    ├── sandcastle-prompt.md    # Prompt template (injects commits, inputs, prompt.md)
    ├── Dockerfile              # Container image (Node 22, gh CLI, Claude Code)
    └── .env.example            # Template for tokens (CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, GH_REPO)
```

## How Each Runner Works

### Ralph (Docker)

1. `afk.sh` builds input from issues/files
2. Reads `afk/ralph/prompt.md` directly (via `$SCRIPT_DIR`)
3. Spins up a `ralph-runner` Docker container with the project bind-mounted
4. Runs `claude --print` inside the container
5. Streams output via jq filters

### Sandcastle

1. `afk.sh` builds input from issues/files
2. Copies `afk/sandcastle/prompt.md` → `ralph/prompt.md` (because `.sandcastle/sandcastle-prompt.md` hardcodes that path)
3. Delegates to `npx tsx .sandcastle/main.ts`
4. Sandcastle manages the container lifecycle, hooks, and streaming

## File Conflict Note

Both runners have their own `prompt.md`. There is no conflict:

- **Ralph** reads `afk/ralph/prompt.md` directly — never touches `ralph/prompt.md`
- **Sandcastle** copies `afk/sandcastle/prompt.md` → `ralph/prompt.md` before each run (because `.sandcastle/sandcastle-prompt.md` hardcodes `cat ralph/prompt.md`)

Running them back-to-back or even simultaneously is safe. Ralph ignores `ralph/prompt.md` entirely.

## Differences

|                 | Ralph                                    | Sandcastle                                             |
| --------------- | ---------------------------------------- | ------------------------------------------------------ |
| Runtime         | Custom `docker run`                      | `@ai-hero/sandcastle` library                          |
| Container image | `ralph-runner` (from `Dockerfile.ralph`) | `sandcastle:*` (from `.sandcastle/Dockerfile`)         |
| Auth            | `~/.claude_auth.txt` + `gh auth token`   | `.sandcastle/.env`                                     |
| Logs            | Streams to terminal via jq               | `tail -f .sandcastle/logs/<branch>.log`                |
| Config          | All in `afk.sh`                          | Split across `main.ts`, `sandcastle-prompt.md`, `.env` |
| Prompt loading  | Reads own copy directly                  | Copies to `ralph/prompt.md` for Sandcastle to find     |

## Prompt Contents

Both `prompt.md` files are identical. They tell Ralph to:

- Pick ONE issue from the provided list
- Fetch full issue body via `gh issue view --repo "$GH_REPO"`
- Implement only what the issue describes
- Run tests and typecheck before committing
- Close the issue via `gh issue close --repo "$GH_REPO"`
- Never fix unrelated code or skip hooks

## Without GitHub: Alternative Issue Backends

The workflow doesn't require GitHub. Ralph needs two things: a list of tasks to pick from, and a way to mark them done. Replace `gh` with whatever your team uses.

| Backend | How Ralph gets tasks | How Ralph closes them |
|---------|---------------------|----------------------|
| Jira | `curl` Jira REST API to list tickets | `curl` to transition ticket to Done |
| Linear | `linear` CLI or API | Same CLI/API to close |
| GitLab | `glab issue list` (GitLab CLI) | `glab issue close` |
| Azure DevOps | `az boards work-item list` | `az boards work-item update --state Done` |
| Markdown file | `cat plans/backlog.md` | Edit the file to mark `[x]` and commit |
| Plain text file | `cat TODO.txt` | Remove or mark the line |

The simplest zero-dependency approach is a **markdown backlog file**:

```markdown
# Backlog

- [ ] #1: XP schema + service + award on lesson completion
- [ ] #2: Leveling pure calculation utility
- [ ] #3: Streaks schema + service
- [x] #4: Already done
```

To use this instead of GitHub:
1. In `afk.sh`, replace `gh issue list` with `cat plans/backlog.md`
2. In `prompt.md`, replace the `gh issue view/close` instructions with: "Pick one unchecked `- [ ]` item, implement it, then mark it `- [x]` and commit the file"
3. Remove `GH_TOKEN` and `GH_REPO` — not needed

No API, no CLI tools, no auth tokens. Works with any git host or no git host at all.

## Lessons Learned (why we customized these files)

| Problem                   | What Ralph did wrong                                       | How we fixed it                                                       |
| ------------------------- | ---------------------------------------------------------- | --------------------------------------------------------------------- |
| Wrong repo                | `gh` defaulted to upstream — read wrong issue #1           | `GH_REPO` env var + `--repo "$GH_REPO"` on all `gh` commands          |
| Ignored the issue         | Worked on unrelated bookmarks instead of assigned task     | Prompt: "ONLY implement what the provided GitHub issue describes"     |
| Fixed unrelated code      | Fixed typecheck errors in files it didn't need to touch    | Prompt: "Do NOT fix unrelated code, even if it has errors"            |
| Skipped hooks             | Used `git commit --no-verify` when tests couldn't run      | Prompt: "NEVER use git commit --no-verify"                            |
| Lied about closing issues | Said "issue already closed" when it wasn't                 | Explicit `gh issue close` command template with `--repo` in prompt    |
| Context too large         | Passing 20 full issue bodies would exceed token limits     | `afk.sh` passes only titles+numbers; Ralph fetches the one it picks   |
| node_modules crash        | macOS binaries in bind-mounted node_modules crash on Linux | Ralph uses a Docker named volume; Sandcastle runs `pnpm install` hook |
