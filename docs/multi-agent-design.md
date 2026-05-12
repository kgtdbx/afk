# Multi-Agent AFK Design

Make the agent a flag, not a folder. One script, one Docker image, any agent.

---

## Usage

```bash
./ralph/afk.sh 5 --agent claude                     # default (backwards compatible)
./ralph/afk.sh 5 --agent codex --issue 3
./ralph/afk.sh 5 --agent gemini --file plans/plan.md
./ralph/afk.sh 5                                     # same as --agent claude
```

---

## Architecture: What Changes vs What's Shared

```
  +================================================================+
  |                    SHARED (agent-agnostic)                      |
  |                                                                 |
  |  afk.sh:                                                       |
  |    - Arg parsing (--issue, --file, iterations)                 |
  |    - Input building (gh issue list / gh issue view / cat file) |
  |    - Prompt assembly (commits + inputs + prompt.md)            |
  |    - Loop structure (for i in 1..N)                            |
  |    - Completion signal check (<promise>NO MORE TASKS</promise>)|
  |                                                                 |
  |  Docker:                                                        |
  |    - Single image with ALL agent CLIs installed                |
  |    - Bind mount project into /workspace                        |
  |    - Named volume for node_modules                             |
  |    - pnpm install --frozen-lockfile                            |
  |    - GH_TOKEN + GH_REPO env vars                               |
  |                                                                 |
  |  prompt.md:                                                     |
  |    - Task selection, implementation, commit, close issue        |
  |    - Fully agent-agnostic (natural language instructions)      |
  |                                                                 |
  +================================================================+

  +================================================================+
  |                  PER-AGENT (selected by --agent flag)           |
  |                                                                 |
  |  1. CLI command + flags                                        |
  |  2. Auth env var name + auth file path                         |
  |  3. Output parsing (how to extract final result)               |
  |  4. Permission/sandbox flag                                    |
  |                                                                 |
  +================================================================+
```

---

## Agent Config Block

```bash
AGENT="${AGENT:-claude}"   # default to claude

case "$AGENT" in
  claude)
    AGENT_AUTH_VAR="CLAUDE_CODE_OAUTH_TOKEN"
    AGENT_AUTH_FILE="$HOME/.claude_auth.txt"
    # Claude uses --print (one-shot) + stream-json output
    # Output parsing: jq to extract final result
    ;;
  codex)
    AGENT_AUTH_VAR="CODEX_API_KEY"
    AGENT_AUTH_FILE="$HOME/.codex_auth.txt"
    # Codex uses exec (one-shot) + -o tmpfile for final output
    # Output parsing: grep the tmpfile directly
    ;;
  gemini)
    AGENT_AUTH_VAR="GEMINI_API_KEY"
    AGENT_AUTH_FILE="$HOME/.gemini_auth.txt"
    # TBD -- fill in when Gemini CLI is available
    ;;
  *)
    echo "Unknown agent: $AGENT"
    echo "Supported: claude, codex, gemini"
    exit 1
    ;;
esac
```

---

## How Each Agent Runs Inside Docker

### Claude Code

```bash
docker run --rm \
  -v "$PROJECT_DIR":/workspace \
  -v afk_node_modules:/workspace/node_modules \
  -e CLAUDE_CODE_OAUTH_TOKEN="$(cat "$AUTH_FILE")" \
  -e GH_TOKEN="$(gh auth token)" \
  -e GH_REPO="$GH_REPO" \
  "$IMAGE" \
  bash -c 'pnpm install --frozen-lockfile 2>/dev/null; claude \
    --dangerously-skip-permissions \
    --print \
    --output-format stream-json \
    "$PROMPT"'
```

Output parsing:
```
  claude --print --output-format stream-json
    |
    v
  JSON stream to stdout
    |
    v
  grep '^{'              filter noise
    |
    v
  tee "$tmpfile"         save + display
    |
    v
  jq "$stream_filter"   format for terminal
    |
    v
  jq "$final_result" "$tmpfile"   extract final output
    |
    v
  check for NO MORE TASKS
```

### Codex

```bash
docker run --rm \
  -v "$PROJECT_DIR":/workspace \
  -v afk_node_modules:/workspace/node_modules \
  -e CODEX_API_KEY="$(cat "$AUTH_FILE")" \
  -e GH_TOKEN="$(gh auth token)" \
  -e GH_REPO="$GH_REPO" \
  "$IMAGE" \
  bash -c 'pnpm install --frozen-lockfile 2>/dev/null; codex exec \
    -s danger-full-access \
    -o /tmp/result.txt \
    "$PROMPT"; cat /tmp/result.txt'
```

Output parsing:
```
  codex exec -o /tmp/result.txt
    |
    v
  Progress to stderr (visible in terminal)
  Final message written to /tmp/result.txt
    |
    v
  cat /tmp/result.txt    pipe out of container
    |
    v
  tee "$tmpfile"         save locally
    |
    v
  grep "NO MORE TASKS" "$tmpfile"   check completion
```

### Gemini (future)

```bash
docker run --rm \
  -v "$PROJECT_DIR":/workspace \
  -v afk_node_modules:/workspace/node_modules \
  -e GEMINI_API_KEY="$(cat "$AUTH_FILE")" \
  -e GH_TOKEN="$(gh auth token)" \
  -e GH_REPO="$GH_REPO" \
  "$IMAGE" \
  bash -c 'pnpm install --frozen-lockfile 2>/dev/null; gemini \
    <flags TBD> \
    "$PROMPT"'
```

Output parsing: TBD when Gemini CLI is available.

---

## Single Docker Image

One image with all agent CLIs installed. The `--agent` flag picks which
CLI to invoke at runtime.

### Dockerfile

```dockerfile
FROM node:22-bookworm

# System deps
RUN apt-get update && apt-get install -y \
  git curl jq python3 make g++ \
  && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
  https://cli.github.com/packages stable main" \
  | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
  && apt-get update && apt-get install -y gh \
  && rm -rf /var/lib/apt/lists/*

RUN corepack enable

# Match macOS host user UID/GID for bind mount permissions
RUN usermod -d /home/agent -m -l agent -u 503 -g 20 node
USER agent

# ---- Agent CLIs (all in one image) ----

# Claude Code
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:$PATH"

# Codex
RUN npm i -g @openai/codex

# Gemini (uncomment when available)
# RUN npm i -g @google/gemini-cli

WORKDIR /workspace
ENTRYPOINT ["sleep", "infinity"]
```

### Why one image?

```
  Separate images:                    Single image:
  ================                    =============

  ralph-runner   ~800 MB              afk-runner   ~850 MB
  codex-runner   ~780 MB
  gemini-runner  ~780 MB              Total: 850 MB
  Total: ~2.3 GB                      (all CLIs are small)

  3 images to build/maintain          1 image to build/maintain
  Rebuild when switching agents       Switch agents with a flag
```

---

## Data Flow: Agent-Agnostic Loop

```
  User runs:  ./ralph/afk.sh 5 --agent codex --issue 3

  +--[afk.sh]--------------------------------------------------+
  |                                                              |
  |  1. Parse args: iterations=5, agent=codex, issue=3          |
  |  2. Load agent config (case block)                          |
  |  3. Validate auth file exists                               |
  |  4. Build inputs (gh issue view #3)                         |
  |  5. Detect Docker image, build if needed                    |
  |                                                              |
  |  +--[LOOP i=1..5]------------------------------------------+|
  |  |                                                          ||
  |  |  6. commits = git log -n 5                              ||
  |  |  7. prompt = commits + inputs + prompt.md               ||
  |  |                                                          ||
  |  |  8. docker run --rm                                     ||
  |  |     +--[Container]----------------------------------+   ||
  |  |     |                                                |   ||
  |  |     |  9. pnpm install --frozen-lockfile             |   ||
  |  |     | 10. $AGENT_CMD "$prompt"                       |   ||
  |  |     |     ^^^^^^^^^^                                 |   ||
  |  |     |     claude --print  (if --agent claude)        |   ||
  |  |     |     codex exec      (if --agent codex)         |   ||
  |  |     |                                                |   ||
  |  |     +--(container destroyed)------------------------+   ||
  |  |                                                          ||
  |  | 11. Parse output ($PARSE_OUTPUT method)                 ||
  |  | 12. Check for NO MORE TASKS                             ||
  |  |     yes --> exit 0                                      ||
  |  |     no  --> next iteration                              ||
  |  |                                                          ||
  |  +----------------------------------------------------------+|
  |                                                              |
  +--------------------------------------------------------------+
```

---

## Migration Path

```
  Phase 1: Current state (no changes needed)
  ============================================
  ./ralph/afk.sh 5                  # works exactly as before
                                    # --agent defaults to claude

  Phase 2: Add --agent flag
  ============================================
  ./ralph/afk.sh 5 --agent claude   # same as Phase 1
  ./ralph/afk.sh 5 --agent codex    # new! uses Codex CLI

  Phase 3: Add more agents (when available)
  ============================================
  ./ralph/afk.sh 5 --agent opencode  # new! uses OpenCode
  # Add new agents to the case block + Dockerfile as needed
```

Backwards compatible at every phase. No existing behavior changes.

---

## Files to Change

| File | Change | Why |
|------|--------|-----|
| `ralph/afk.sh` | Add `--agent` flag + case block | Route to correct CLI |
| `ralph/afk.sh` | Add per-agent run + parse functions | Different CLI invocation and output |
| `Dockerfile.ralph` | Install all agent CLIs | Single image for all agents |
| `sandcastle/main.ts` | Accept agent arg, map to factory | Sandcastle multi-agent support |
| `sandcastle/afk.sh` | Pass `$AGENT` to main.ts | Forward agent selection |
| `prompt.md` | No change | Already agent-agnostic |

No new folders. No new repos. No duplication.

---

## Sandcastle: Also Supports Multiple Agents

Sandcastle (`@ai-hero/sandcastle`) is NOT locked to Claude Code.
It exports multiple agent factories:

```typescript
export { claudeCode, codex, opencode, pi } from "./AgentProvider.js";
```

### Switching agents in `sandcastle/main.ts`

```typescript
  // Current (Claude Code):
  import { run, claudeCode } from "@ai-hero/sandcastle";

  await run({
    agent: claudeCode("claude-sonnet-4-6"),
    ...
  });

  // Codex (one-word change):
  import { run, codex } from "@ai-hero/sandcastle";

  await run({
    agent: codex("gpt-5.2-codex"),
    ...
  });

  // OpenCode:
  import { run, opencode } from "@ai-hero/sandcastle";

  await run({
    agent: opencode("some-model"),
    ...
  });
```

Same pattern, same API. Swap the factory function and model string.

### Available agents in Sandcastle

```
  Factory Function    Agent CLI          Import
  ================    =========          ======
  claudeCode()        Claude Code        import { claudeCode } from "@ai-hero/sandcastle"
  codex()             Codex CLI          import { codex } from "@ai-hero/sandcastle"
  opencode()          OpenCode           import { opencode } from "@ai-hero/sandcastle"
  pi()                Pi                 import { pi } from "@ai-hero/sandcastle"
```

### How to make `sandcastle/main.ts` support --agent

The `sandcastle/afk.sh` script calls `main.ts` via:

```bash
npx tsx .sandcastle/main.ts "$inputs" "$MAX_ITER"
```

Add the agent as a third argument:

```bash
npx tsx .sandcastle/main.ts "$inputs" "$MAX_ITER" "$AGENT"
```

Then in `main.ts`:

```typescript
import { run, claudeCode, codex } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

const [, , planAndPrd, maxIterations, agentName] = process.argv;

const agents: Record<string, () => AgentProvider> = {
  claude: () => claudeCode("claude-sonnet-4-6"),
  codex:  () => codex("gpt-5.2-codex"),
};

const selectedAgent = agents[agentName || "claude"];
if (!selectedAgent) {
  console.error(`Unknown agent: ${agentName}. Supported: ${Object.keys(agents).join(", ")}`);
  process.exit(1);
}

await run({
  sandbox: docker(),
  agent: selectedAgent(),
  promptFile: `.sandcastle/sandcastle-prompt.md`,
  maxIterations: Number(maxIterations) ?? 3,
  promptArgs: {
    INPUTS: planAndPrd,
  },
  hooks: {
    onSandboxReady: [{ command: "pnpm rebuild" }],
  },
  completionSignal: "<promise>NO MORE TASKS</promise>",
});
```

### Both runners support multi-agent

```
  Runner          How agent is selected           What changes
  ======          =======================         ============

  ralph/afk.sh    --agent flag (bash case block)  run_claude() or run_codex()
  sandcastle      --agent flag (passed to main.ts) codex() or claudeCode()
```

---

## Skills: Shared Across Agents

Claude Code and Codex both use the **same SKILL.md format** (the Agent Skills
open standard). The content is identical — only the discovery path and
invocation syntax differ.

### Format Comparison

```
  SKILL.md format (identical for both):
  ======================================

  ---
  name: tdd
  description: Test-driven development with red-green-refactor loop
  ---

  # Instructions

  1. Write a failing test
  2. Implement minimal code to pass
  3. Refactor
  ...
```

### Discovery Paths

```
  Claude Code reads from:          Codex reads from:
  =======================          =================

  .claude/skills/                  .agents/skills/
  ~/.claude/skills/                ~/.agents/skills/
                                   /etc/codex/skills/
```

### Invocation

```
  Claude Code:   /tdd              (slash command)
  Codex:         $tdd              (dollar-sign mention)
  Both:          auto-invoke when task matches description
```

### The Symlink Approach: One Skill, Both Agents

Instead of duplicating skills, symlink the same directory into both paths:

```bash
# Project structure (single source of truth):
.claude/skills/
  tdd/SKILL.md
  do-work/SKILL.md
  write-a-prd/SKILL.md

# Symlink so Codex sees them too:
mkdir -p .agents/skills
ln -s ../../.claude/skills/tdd .agents/skills/tdd
ln -s ../../.claude/skills/do-work .agents/skills/do-work
ln -s ../../.claude/skills/write-a-prd .agents/skills/write-a-prd
```

Or symlink the entire directory:

```bash
mkdir -p .agents
ln -s ../.claude/skills .agents/skills
```

Result:

```
  .claude/skills/tdd/SKILL.md          <-- the actual file
  .agents/skills/tdd/SKILL.md          <-- symlink to the same file

  Claude Code: /tdd                    reads .claude/skills/tdd/SKILL.md
  Codex:       $tdd                    reads .agents/skills/tdd/SKILL.md
                                       (same file via symlink)
```

### What About Agent-Specific Metadata?

If a skill needs agent-specific config:

```
  Claude Code:  extra frontmatter fields (argument-hint, model, etc.)
  Codex:        agents/openai.yaml sidecar file

  The SKILL.md body stays the same. Agent-specific config goes in
  separate files that the other agent ignores.
```

```
  tdd/
    SKILL.md                  <-- shared instructions
    agents/openai.yaml        <-- Codex-only metadata (optional)
```

Claude Code ignores `agents/openai.yaml`. Codex ignores unknown frontmatter
fields. No conflict.

### Automation: Symlink All Skills in Setup

Add to the project setup or `codex-setup.sh`:

```bash
# Create .agents/skills as symlink to .claude/skills
if [ -d ".claude/skills" ] && [ ! -e ".agents/skills" ]; then
  mkdir -p .agents
  ln -s ../.claude/skills .agents/skills
fi
```

This way any skill created for Claude Code is automatically available to
Codex, and vice versa.

### Gotcha: YAML Frontmatter Required for Codex

Claude Code loads skills with or without YAML frontmatter. **Codex requires
it.** Without `---` delimiters + `name` + `description`, Codex skips the skill
with a warning.

```
  Claude Code:   frontmatter optional (uses folder name + first line)
  Codex:         frontmatter REQUIRED (skips skill without it)
```

If you see this error in Codex:

```
  Skipped loading 4 skill(s) due to invalid SKILL.md files.
  missing YAML frontmatter delimited by ---
```

Add frontmatter to each SKILL.md:

```markdown
---
name: skill-name
description: What this skill does. Use when [triggers].
---

# Rest of the skill content...
```

This is backwards compatible — Claude Code reads the frontmatter too when
present. So always include it.

### Verified Working (tested 2026-05-11)

```
  Symlink approach:    WORKS
  Shared SKILL.md:     WORKS (with frontmatter)
  Claude Code /skill:  WORKS
  Codex $skill:        WORKS
  Auto-invoke:         WORKS (both agents)
```

### Summary

```
  SKILL.md content:     SAME format, both agents read it
  Skill location:       .claude/skills/ vs .agents/skills/
  Solution:             Symlink .agents/skills --> .claude/skills
  Invocation:           /name (Claude) vs $name (Codex)
  Auto-invoke:          Both support it
  Agent-specific cfg:   Sidecar files, no conflicts
  Frontmatter:          REQUIRED for Codex, optional for Claude Code
                        (always include it for compatibility)
```

Sources:
- [Codex Skills](https://developers.openai.com/codex/skills)
- [AGENTS.md Guide](https://developers.openai.com/codex/guides/agents-md)
- [Agent Skills Open Standard](https://www.thepromptindex.com/how-to-use-ai-agent-skills-the-complete-guide.html)
