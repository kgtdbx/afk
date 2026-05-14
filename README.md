# AFK Runners: Ralph & Sandcastle

Two ways to run the Ralph AFK loop. Same interface, different runtimes. An LLM (or human) can follow these instructions to set up either runner from scratch.

## Table of Contents

- [Prerequisites](#prerequisites-both-runners)
- [Setup: Ralph](#setup-ralph-custom-docker)
- [Setup: Sandcastle](#setup-sandcastle)
- [Setup: Claude Desktop AFK (in-session skill, no Docker)](#setup-claude-desktop-afk-in-session-skill-no-docker)
- [Using Codex Instead of Claude Code](#using-codex-instead-of-claude-code)
- [Where to Run From](#where-to-run-from)
- [Usage](#usage-identical-for-both-runners)
- [Directory Structure](#directory-structure)
- [How Each Runner Works](#how-each-runner-works)
- [File Conflict Note](#file-conflict-note)
- [Differences](#differences)
- [Prompt Contents](#prompt-contents)
- [Without GitHub: Alternative Issue Backends](#without-github-alternative-issue-backends)
- [Lessons Learned](#lessons-learned-why-we-customized-these-files)

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

## Setup: Claude Desktop AFK (in-session skill, no Docker)

A third option that runs the AFK loop **inside an existing Claude session** (Claude Desktop or `claude` CLI) instead of spinning up Docker containers per iteration. Lives in `afk/skills/afk/` as a Claude Code skill. No Docker, no auth files, no container builds — just a SKILL.md plus a small `build-prompt.sh` that gathers the same inputs Ralph would gather (last-5 commits + open issue titles + `prompt.md`).

Each `/afk` invocation = ONE iteration. The outer loop is owned either by the user's prompt phrasing ("keep going until all issues are done") or by Claude Code's `/loop` command. The completion sentinel `<promise>NO MORE TASKS</promise>` is preserved from upstream so loops still stop cleanly.

### Step 1: Install the skill into the project

```bash
# From the target project root, with this afk repo already copied into
# ./afk/ (same convention as Ralph/Sandcastle setup).
mkdir -p .claude/skills/afk
cp afk/skills/afk/SKILL.md       .claude/skills/afk/
cp afk/skills/afk/build-prompt.sh .claude/skills/afk/
chmod +x .claude/skills/afk/build-prompt.sh
```

Or, to make it available across every project, install it user-wide:

```bash
# Run from inside a checkout of this afk repo
mkdir -p ~/.claude/skills/afk
cp skills/afk/SKILL.md       ~/.claude/skills/afk/
cp skills/afk/build-prompt.sh ~/.claude/skills/afk/
chmod +x ~/.claude/skills/afk/build-prompt.sh
```

### Step 2: Verify `prompt.md` is reachable

The skill reads `prompt.md` automatically and resolves it in this order:

1. `$AFK_PROMPT_MD` (if set)
2. `<repo>/afk/ralph/prompt.md`
3. `<repo>/ralph/prompt.md`

If you copied the full `afk/` directory into your target project (as the install step assumes), `afk/ralph/prompt.md` is already there — confirm with `ls afk/ralph/prompt.md` and move on. If you installed user-wide and your project doesn't have an `afk/` directory yet, point the skill at any `prompt.md` you have with `export AFK_PROMPT_MD=/path/to/prompt.md`.

### Step 3: Authenticate `gh` and ensure the project builds

Same prerequisites as Ralph: `gh auth login`, `pnpm install` in the project root.

### Step 4: Enable auto-accept so the loop is truly AFK

This is the trick. Without it, every `Bash` / `Edit` / `Write` tool call triggers a permission prompt that you have to approve manually — which defeats the entire AFK premise.

**Claude Desktop:**
- Toggle **Auto-accept edits** / **auto mode** on in the session's permission menu. Once enabled, the session will execute tool calls without prompting.

**`claude` CLI:**
- Launch with `--dangerously-skip-permissions`:
  ```bash
  claude --dangerously-skip-permissions
  ```
- Or toggle bypass-permissions mode via `/permission-mode` inside an existing session.

### Step 5: Kick off the loop

Open the project in Claude Desktop (or the CLI), make sure auto-accept is on, then send a single prompt like:

```
/afk work on the remaining issues of this project, https://github.com/<owner>/<repo>/issues
don't prompt me for anything, just work on it until all issues are done
```

The first line invokes the skill. The free-form instructions after it tell the model to keep iterating across issues, not just do one and stop. The model will:

1. Run `build-prompt.sh` to assemble the iteration prompt (commits + issues + `prompt.md`).
2. Pick one issue per iteration per `prompt.md`'s priority rules.
3. Implement, run `pnpm run test` + `pnpm run typecheck`, commit, close the issue.
4. Append a line to `<repo>/afk/logs/<branch>.log`.
5. Loop until no actionable work remains, then emit `<promise>NO MORE TASKS</promise>`.

### Equivalent invocations

```text
# All open issues, loop until done
/afk work on the remaining issues, don't prompt me, just work until all issues are done

# A single issue
/afk --issue 12

# A PRD file
/afk --file plans/gamification-prd.md

# Mix
/afk --issue 3 --issue 5 --file plans/refactor.md
```

To use Claude Code's own `/loop` machinery instead of free-form "keep going" phrasing, prefix with `/loop`:

```
/loop /afk
/loop /afk --issue 12
```

`/loop` re-fires `/afk` each turn and stops when the sentinel fires.

For when to pick this workflow vs Ralph/Sandcastle — and the tradeoffs around shared context, compaction, auto-accept, and containment — see [docs/AIHERO-HIGH_LEVEL_WORKFLOWS.md → Claude Desktop AFK Workflow](docs/AIHERO-HIGH_LEVEL_WORKFLOWS.md#workflow-1b-claude-desktop-afk-in-session-no-docker).

## Using Codex Instead of Claude Code

Both runners support `--agent codex` to use OpenAI Codex instead of Claude Code.

### Prerequisites (Codex — both runners)

- Codex CLI installed on your Mac: `npm i -g @openai/codex`
- Authenticated on your Mac: `codex login` (credentials at `~/.codex/auth.json`)

### Setup: Ralph with Codex

Rebuild the Docker image (it now includes both Claude Code and Codex CLI):

```bash
docker build -t ralph-runner -f Dockerfile.ralph .
```

That's it. Ralph mounts `~/.codex/` into the container automatically.

### Setup: Sandcastle with Codex

Rebuild the Sandcastle Docker image (it now includes Codex CLI + Corepack fixes):

```bash
pnpm sandcastle docker build-image
```

No `.env` changes needed — Sandcastle's `main.ts` automatically mounts `~/.codex/` into the container when the directory exists on your Mac. Codex uses the credentials from `codex login`, not the `.env` file.

### Run with Codex

```bash
# Ralph runner with Codex
./afk/ralph/afk.sh 100 --agent codex

# Sandcastle runner with Codex
./afk/sandcastle/afk.sh 100 --agent codex

# Mix with other flags
./afk/ralph/afk.sh 100 --agent codex --issue 3
./afk/sandcastle/afk.sh 100 --agent codex --file plans/prd.md
```

Default is `--agent claude` (backwards compatible). Running without `--agent` works exactly as before.

### Skills Compatibility

Both Claude Code and Codex use the same SKILL.md format. Symlink skills so both agents see them:

```bash
mkdir -p .agents
ln -s ../.claude/skills .agents/skills
```

Codex requires YAML frontmatter in SKILL.md (Claude Code doesn't). Always include it:

```markdown
---
name: skill-name
description: What it does. Use when [triggers].
---

# Rest of instructions...
```

Invoke skills in Codex with `$skill-name` (vs `/skill-name` in Claude Code).

### Logs

Ralph logs to `ralph/logs/<branch>.log`. Watch in another terminal:

```bash
tail -f ralph/logs/<branch-name>.log
```

### Full Workflow (tested)

```bash
# 1. Create issues from a PRD (inside Codex interactive)
$prd-to-issues #1

# 2. AFK loop — implement all issues
./afk/ralph/afk.sh 100 --agent codex

# 3. AFK loop again — PRD review and QA
./afk/ralph/afk.sh 100 --agent codex
```

---

## Where to Run From

Always run from the project root:

```bash
cd /Users/krl/Documents/dev/cohort-003-project-main
./afk/sandcastle/afk.sh 5
```

The scripts use `git remote` and `gh issue list` early on (before resolving paths), so they need to be inside the git repo. Running from the project root guarantees everything works — `git`, `gh`, relative file paths, and Sandcastle's `npx tsx` all resolve correctly.

## Usage (identical for both runners)

```bash
# Pick from all open GitHub issues (default, uses Claude Code)
./ralph/afk.sh 100

# Use Codex instead
./ralph/afk.sh 100 --agent codex

# Specific issues
./ralph/afk.sh 100 --issue 1 --issue 2

# Plan/PRD files
./ralph/afk.sh 100 --file plans/plan.md --file plans/prd.md

# Mix everything (any combo, any order, repeatable)
./ralph/afk.sh 100 --agent codex --issue 1 --file plans/prd.md --issue 12
```

## Directory Structure

```
afk/
├── ralph/                      # Custom Docker container runner
│   ├── afk.sh                  # Entry point
│   ├── prompt.md               # Ralph's instructions (read directly via $SCRIPT_DIR;
│   │                           #   also the canonical source the in-session skill resolves)
│   └── Dockerfile.ralph        # Container image definition
│
├── sandcastle/                 # Sandcastle library runner
│   ├── afk.sh                  # Entry point
│   ├── prompt.md               # Ralph's instructions (copied to ralph/prompt.md at runtime)
│   ├── main.ts                 # Sandcastle config (agent, model, hooks, completion signal)
│   ├── sandcastle-prompt.md    # Prompt template (injects commits, inputs, prompt.md)
│   ├── Dockerfile              # Container image (Node 22, gh CLI, Claude Code)
│   └── .env.example            # Template for tokens (CLAUDE_CODE_OAUTH_TOKEN, GH_TOKEN, GH_REPO)
│
└── skills/afk/                 # Claude Desktop / in-session skill (no Docker)
    ├── SKILL.md                # Skill definition + per-iteration instructions
    └── build-prompt.sh         # Assembles commits + issues/files + prompt.md to stdout
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

|                 | Ralph                                    | Sandcastle                                             | Claude Desktop AFK (skill)                                  |
| --------------- | ---------------------------------------- | ------------------------------------------------------ | ----------------------------------------------------------- |
| Runtime         | Custom `docker run`                      | `@ai-hero/sandcastle` library                          | Current Claude session (Desktop or `claude` CLI)            |
| Container image | `ralph-runner` (from `Dockerfile.ralph`) | `sandcastle:*` (from `.sandcastle/Dockerfile`)         | None — runs in your existing session                        |
| Agents          | Claude Code + Codex (`--agent` flag)     | Claude Code + Codex (`--agent` flag)                   | Whichever model the session is using (Claude only)          |
| Auth (Claude)   | `~/.claude_auth.txt`                     | `.sandcastle/.env`                                     | Existing session login — no extra auth file                 |
| Auth (Codex)    | `~/.codex/auth.json` (mounted into container) | `.sandcastle/.env`                                | N/A                                                          |
| Logs            | `ralph/logs/<branch>.log`                | `.sandcastle/logs/<branch>.log`                        | `<repo>/afk/logs/<branch>.log` (per the skill)              |
| Config          | All in `afk.sh`                          | Split across `main.ts`, `sandcastle-prompt.md`, `.env` | `SKILL.md` + `build-prompt.sh`                              |
| Prompt loading  | Reads own copy directly                  | Copies to `ralph/prompt.md` for Sandcastle to find     | Resolves `$AFK_PROMPT_MD` → `afk/ralph/prompt.md` → `ralph/prompt.md` |
| Outer loop      | `MAX_ITER` in `afk.sh`                   | `MAX_ITER` in `afk.sh`                                 | User's prompt phrasing or Claude Code's `/loop`             |
| Isolation       | Docker is the trust boundary             | Docker is the trust boundary                           | Same trust boundary as your shell — needs hooks for fencing |

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

For lessons learned from porting to Codex (auth, skills, Docker, Sandcastle fixes), see [docs/lessons-learned-codex-port.md](docs/lessons-learned-codex-port.md).
