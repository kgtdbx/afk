# Lessons Learned: Porting AFK from Claude Code to Codex


---

## 1. Codex Setup Script Has Internet — Agent Phase Doesn't

```
  Initial assumption (WRONG):
  ============================
  "Codex has no internet. Must pre-install everything offline."

  Actual behavior:
  ================
  Setup script: internet ON   --> pnpm install works
  Agent phase:  internet OFF  --> local tools only (test, typecheck, git)
```

`-s danger-full-access` on CLI removes ALL restrictions including network.

---

## 2. SKILL.md Frontmatter Required for Codex

Claude Code loads skills with or without YAML frontmatter.
Codex silently skips them without it.

```
  ERROR:
  Skipped loading 4 skill(s) due to invalid SKILL.md files.
  missing YAML frontmatter delimited by ---

  FIX: Add to top of every SKILL.md:
  ---
  name: skill-name
  description: What it does. Use when [triggers].
  ---
```

Always include frontmatter — it's backwards compatible with Claude Code.

---

## 3. Skills Symlink Works

```bash
ln -s ../.claude/skills .agents/skills
```

One set of skills, both agents see them. Tested and confirmed working.

```
  Claude Code:  /prd-to-issues #1    --> reads .claude/skills/prd-to-issues/SKILL.md
  Codex:        $prd-to-issues #1    --> reads .agents/skills/prd-to-issues/SKILL.md
                                         (same file via symlink)
```

---

## 4. Codex Auth: Mount the Credential Store, Don't Pass Keys

```
  First attempt (WRONG):
  -e CODEX_API_KEY="$(cat ~/.codex_auth.txt)"

  Correct approach:
  -v "$HOME/.codex":/home/ralph/.codex
```

Codex stores credentials in `~/.codex/auth.json` via `codex login`.
Mount the whole directory into the container instead of extracting keys.

---

## 5. `codex exec` is the Equivalent of `claude --print`

```
  Claude Code (one-shot):            Codex (one-shot):
  =======================            =================

  claude --print "$PROMPT"           codex exec "$PROMPT"
  --dangerously-skip-permissions     -s danger-full-access
  --output-format stream-json        --json (or -o tmpfile)
```

Output parsing is simpler with Codex: use `-o tmpfile` to capture the
final message, then `grep` for the completion signal. No jq needed.

---

## 6. Sandcastle Already Supports Codex

```typescript
// Don't need a new library or framework:
import { claudeCode, codex } from "@ai-hero/sandcastle";

// Claude:
agent: claudeCode("claude-opus-4-6")

// Codex (one-word swap):
agent: codex("gpt-5.5")
```

Same API, same `run()` function, same Docker sandbox. Just swap the
factory function.

---

## 7. Don't Hardcode Model Versions

```
  BAD:   claudeCode("claude-sonnet-4-6")    --> stale in 3 months
  BAD:   codex("gpt-5.2-codex")             --> already outdated

  OK:    claudeCode("claude-opus-4-6")      --> current, but will age
  OK:    codex("gpt-5.5")                   --> current, but will age
```

Ralph (bash) doesn't pass `--model` to Claude — it uses whatever the
system defaults to. This is the most future-proof approach. Sandcastle
requires a model string, so it has to be updated when models change.

---

## 8. Don't Rename Docker Images/Volumes

```
  First attempt (WRONG):
  IMAGE="afk-runner"                        --> breaks existing setup
  -v afk_node_modules:/workspace/...        --> creates empty volume

  Correct approach:
  IMAGE="ralph-runner"                      --> reuses existing image
  -v ralph_node_modules:/workspace/...      --> reuses existing volume
```

Renaming Docker images or volumes orphans the existing ones and forces
a full rebuild/reinstall.

---

## 9. `pnpm reset` Wipes Untracked Files

Running `pnpm reset` (ai-hero-cli) does a `git reset --hard` which
deletes all uncommitted changes AND untracked files in tracked directories.

```
  Lost during reset:
  - Modified afk/ files (uncommitted changes)
  - New docs/ files (untracked)

  Survived the reset:
  - docs/ files (if in an untracked directory that git doesn't manage)
```

Commit or copy files to a safe location before running reset.

---

## 10. One Docker Image for All Agents

```dockerfile
# ---- Agent CLIs ----
RUN npm install -g @anthropic-ai/claude-code
RUN npm install -g @openai/codex
```

Both CLIs are small. One image is simpler than maintaining separate ones.
The `--agent` flag selects which CLI runs at runtime.

---

## 11. Add Logging — You'll Need It

Ralph originally had no log file. When sharing agent output with another
LLM or debugging a run, you need a persistent log.

```bash
LOG_FILE="$PROJECT_DIR/ralph/logs/${BRANCH}.log"
exec > >(tee -a "$LOG_FILE") 2>&1
```

Sandcastle already logs to `.sandcastle/logs/<branch>.log`. Match that
pattern for ralph.

---

## 12. The Full Workflow Works End-to-End

Tested on `cohort-003-project-kgt-codex` with Codex (gpt-5.5):

```
  Step 1: Create issues from PRD
  ==============================
  Ran $prd-to-issues #1 inside Codex interactive mode.
  Codex broke the PRD into GitHub issues automatically.

  Step 2: AFK loop — implement all issues
  ========================================
  ./afk/ralph/afk.sh 100 --agent codex

  Codex picked up each open issue, implemented it, committed,
  and closed it. Ran until only PRD and QA issues remained.

  Step 3: AFK loop — PRD review and QA
  =====================================
  Ran the loop again. Codex went through the PRD and QA
  checklists, found issues, fixed them, and committed.

  Result: working app with the new feature.
```

The full pipeline — PRD to issues to implementation to QA — ran
with Codex as the agent using the same Ralph AFK loop originally
built for Claude Code. No manual coding required.

---

## 13. Sandcastle Docker: Corepack Prompts Block Non-Interactive Containers

Corepack prompts to download pnpm when the project's `packageManager` field
requests a version not already cached. This blocks indefinitely in a
non-interactive Docker container.

```
  ERROR:
  Command failed in sandbox (pnpm rebuild):
  ! Corepack is about to download https://registry.npmjs.org/pnpm/-/pnpm-9.12.3.tgz

  FIX: Set these ENV vars in the Dockerfile:
  ENV COREPACK_ENABLE_NETWORK=1 COREPACK_ENABLE_AUTO_PIN=0 COREPACK_ENABLE_DOWNLOAD_PROMPT=0
  RUN corepack enable && corepack prepare pnpm@9.12.3 --activate
```

`COREPACK_ENABLE_DOWNLOAD_PROMPT=0` is the critical one — it suppresses the
interactive confirmation. The others allow network access and prevent
auto-pinning a different version.

---

## 14. Sandcastle Docker: pnpm Store Path Mismatch

When Sandcastle bind-mounts the host's `node_modules` into the container,
`pnpm rebuild` fails because the symlinks point to the macOS pnpm store
(`/Users/you/Library/pnpm/store/v3`) which doesn't exist inside Linux.

```
  ERROR:
  Unexpected store location
  The dependencies are currently linked from "/Users/krl/Library/pnpm/store/v3"
  pnpm now wants to use "/home/agent/workspace/.pnpm-store/v3"

  FIX: Replace `pnpm rebuild` with `pnpm install --store-dir /tmp/pnpm-store`
  in the onSandboxReady hook:
```

```typescript
hooks: {
  sandbox: {
    onSandboxReady: [{ command: "pnpm install --store-dir /tmp/pnpm-store" }],
  },
},
```

This relinks native modules for Linux using a container-local store.

---

## 15. Sandcastle Docker: Install Codex CLI Before USER Switch

The Sandcastle Dockerfile switches to a non-root user (`agent`) early.
`npm install -g` after the USER switch fails with permission denied.

```
  ERROR:
  npm error The operation was rejected by your operating system.
  npm error path: '/usr/local/lib/node_modules/@openai'

  FIX: Install global packages as root, BEFORE the USER directive:
```

```dockerfile
# Install as root
RUN npm install -g @openai/codex

# Then switch to non-root user
USER agent
```

---

## 16. Sandcastle Docker: Mount ~/.codex for Codex OAuth Auth

Sandcastle's `docker()` sandbox doesn't automatically mount Codex credentials.
Codex inside the container gets 401 Unauthorized because `~/.codex/auth.json`
doesn't exist.

```
  ERROR:
  codex_api::endpoint: failed to connect to websocket: HTTP error: 401 Unauthorized

  FIX: Use the `mounts` option on the docker() sandbox provider:
```

```typescript
sandbox: docker({
  mounts: [
    { hostPath: "~/.codex", sandboxPath: "~/.codex" },
  ],
}),
```

This bind-mounts the host's Codex credential store into the container.
The `codex login` on the host is sufficient — no auth setup needed inside
the container.

---

## Summary Table

| Lesson | Category |
|--------|----------|
| Setup script has internet | Codex architecture |
| SKILL.md needs frontmatter | Skills compatibility |
| Symlink skills across agents | Skills sharing |
| Mount ~/.codex, don't pass keys | Auth |
| `codex exec` = `claude --print` | CLI equivalence |
| Sandcastle has `codex()` built in | Library support |
| Don't hardcode models | Future-proofing |
| Don't rename Docker images | Migration safety |
| `pnpm reset` wipes untracked files | Data loss prevention |
| One Docker image for all agents | Infrastructure |
| Add logging to ralph | Observability |
| Full pipeline works end-to-end | Validation |
| Suppress Corepack download prompt | Sandcastle Docker |
| Use container-local pnpm store | Sandcastle Docker |
| Install global packages before USER | Sandcastle Docker |
| Mount ~/.codex for OAuth auth | Sandcastle Docker |
| Restore host binaries before tsx | Sandcastle host |

---

## 17. Sandcastle: Restore Host Binaries Before Running tsx

`sandcastle/afk.sh` runs `npx tsx` on the **host Mac** before handing off to
Docker. But Sandcastle's container bind-mounts the project and runs
`pnpm install` inside it, overwriting `node_modules/` with **Linux** binaries.

On the next iteration, `npx tsx` on the Mac finds Linux esbuild and crashes:

```
  ERROR:
  "@esbuild/linux-x64" package is present but this platform
  needs the "@esbuild/darwin-x64" package instead.

  ROOT CAUSE:
  1. sandcastle/afk.sh runs npx tsx on Mac           (needs darwin binaries)
  2. Docker container runs pnpm install               (writes linux binaries)
  3. Next iteration: npx tsx on Mac finds linux bins   (crash)

  FIX: Run pnpm install --frozen-lockfile in afk.sh before npx tsx:
```

```bash
# In sandcastle/afk.sh, before npx tsx:
pnpm install --frozen-lockfile 2>/dev/null
```

Ralph doesn't have this problem because it uses a **named Docker volume**
(`ralph_node_modules`) that keeps Linux binaries separate from the host's
`node_modules/`. Sandcastle shares the host's `node_modules/` via bind mount.
