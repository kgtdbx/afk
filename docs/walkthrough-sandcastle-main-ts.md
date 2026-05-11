# Line-by-Line Walkthrough: `sandcastle/main.ts`

## The Full Script (21 lines)

```typescript
import { run, claudeCode } from "@ai-hero/sandcastle";        // 1
import { docker } from "@ai-hero/sandcastle/sandboxes/docker"; // 2

const [, , planAndPrd, maxIterations] = process.argv;          // 4

await run({                                                    // 6
  sandbox: docker(),                                           // 7
  agent: claudeCode("claude-sonnet-4-6"),                      // 8
  promptFile: `.sandcastle/sandcastle-prompt.md`,              // 9
  maxIterations: Number(maxIterations) ?? 3,                   // 10
  promptArgs: {                                                // 11
    INPUTS: planAndPrd,                                        // 12
  },                                                           // 13
  hooks: {                                                     // 14
    onSandboxReady: [{ command: "pnpm rebuild" }],             // 16
  },                                                           // 17
  completionSignal: "<promise>NO MORE TASKS</promise>",        // 18
});                                                            // 19
```

---

## Line by Line

### Lines 1-2: Imports

```typescript
import { run, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
```

```
  @ai-hero/sandcastle = a library that orchestrates the whole loop

  run          = the main function that runs the iteration loop
  claudeCode   = tells Sandcastle "use Claude Code as the AI agent"
  docker       = tells Sandcastle "use Docker containers as sandboxes"
```

Think of it like this:
```
  Sandcastle is the conductor.
  Claude Code is the musician.
  Docker is the rehearsal room.
```

### Line 4: Parse CLI Arguments

```typescript
const [, , planAndPrd, maxIterations] = process.argv;
```

`process.argv` is an array of command-line arguments:
```
  process.argv = [
    "/path/to/node",           // [0] always the Node.js binary
    ".sandcastle/main.ts",     // [1] always the script being run
    "inputs text here...",     // [2] = planAndPrd  (the issues/files text)
    "5"                        // [3] = maxIterations
  ]
```

The `[, ,` skips the first two entries (we don't need them).

This maps to the call in `afk.sh`:
```bash
npx tsx .sandcastle/main.ts "$inputs" "$MAX_ITER"
#                            ^^^^^^^^  ^^^^^^^^^^
#                            argv[2]   argv[3]
```

### Lines 6-19: The `run()` Call

```typescript
await run({
```

`run()` is async -- it returns a Promise. `await` means "wait until it finishes."
This single function call does ALL the work: looping, spawning containers,
running Claude, checking for completion.

### Line 7: Sandbox Configuration

```typescript
  sandbox: docker(),
```

```
  "Use Docker containers as the sandbox."

  What this means:
  +--[Your Mac]----------------------------------+
  |                                               |
  |  main.ts calls run()                          |
  |    |                                          |
  |    +--> For each iteration:                   |
  |           1. Start a new Docker container     |
  |           2. Mount your project into it       |
  |           3. Run Claude inside it             |
  |           4. Destroy the container            |
  |                                               |
  +-----------------------------------------------+
```

### Line 8: Agent Configuration

```typescript
  agent: claudeCode("claude-sonnet-4-6"),
```

```
  "Use Claude Code as the AI agent, with the Sonnet 4.6 model."

  Claude Code = the CLI tool (same thing you're talking to right now)
  claude-sonnet-4-6 = which AI model to use

  Other options could be: claude-opus-4-6, claude-haiku-4-5, etc.
```

### Line 9: Prompt File

```typescript
  promptFile: `.sandcastle/sandcastle-prompt.md`,
```

This is the template file that gets sent to Claude each iteration.
Its contents:
```markdown
<commits>
!`git log -n 5 --format="%H%n%ad%n%B---" --date=short`
</commits>

<inputs>
{{ INPUTS }}
</inputs>

!`cat ralph/prompt.md`
```

The `!` backtick syntax means "run this shell command and insert the output."
The `{{ INPUTS }}` is a template variable filled by `promptArgs`.

### Line 10: Max Iterations

```typescript
  maxIterations: Number(maxIterations) ?? 3,
```

```
  Number("5") = 5      (convert string to number)
  ?? 3                  (if it's null/undefined, default to 3)

  So: run at most 5 iterations (or 3 if not specified)
```

### Lines 11-13: Prompt Arguments

```typescript
  promptArgs: {
    INPUTS: planAndPrd,
  },
```

```
  This fills in the {{ INPUTS }} placeholder in sandcastle-prompt.md

  If planAndPrd = "#1: Add XP\n#2: Streaks"

  Then {{ INPUTS }} in the template becomes:
  "#1: Add XP\n#2: Streaks"
```

### Lines 14-17: Hooks

```typescript
  hooks: {
    onSandboxReady: [{ command: "pnpm rebuild" }],
  },
```

```
  "After the Docker container starts but BEFORE Claude runs,
   execute 'pnpm rebuild' inside the container."

  Timeline:
  +--[Container starts]--+
  |                       |
  |  1. Filesystem ready  |
  |  2. pnpm rebuild      |  <-- onSandboxReady hook runs here
  |  3. Claude starts     |
  |                       |
  +-----------------------+

  Why pnpm rebuild?
  Your Mac compiled native modules (like better-sqlite3) for macOS.
  The Docker container runs Linux. Those binaries won't work.
  "pnpm rebuild" recompiles them for Linux.
```

### Line 18: Completion Signal

```typescript
  completionSignal: "<promise>NO MORE TASKS</promise>",
```

```
  "If Claude's output contains this exact string, stop the loop early."

  Iteration 1: Claude outputs "Fixed issue #3. Committed."
    --> no match --> continue to iteration 2

  Iteration 2: Claude outputs "Fixed issue #7. Committed."
    --> no match --> continue to iteration 3

  Iteration 3: Claude outputs "<promise>NO MORE TASKS</promise>"
    --> MATCH --> stop looping, exit run()
```

---

## Visual: How Sandcastle Orchestrates

```
  afk.sh
    |
    v
  npx tsx .sandcastle/main.ts "$inputs" "5"
    |
    v
  run({...})
    |
    v
  +--[Sandcastle run() internals]----------------------------------+
  |                                                                 |
  |  for iteration = 1 to maxIterations:                           |
  |                                                                 |
  |    1. Create Docker container (sandbox: docker())              |
  |       +--[Container]--------------------------------------+    |
  |       |  - Mount project files                            |    |
  |       |  - Load .env (tokens)                              |    |
  |       +---------------------------------------------------+    |
  |                                                                 |
  |    2. Run onSandboxReady hooks                                 |
  |       +--[Inside container]-------------------------------+    |
  |       |  $ pnpm rebuild                                    |    |
  |       +---------------------------------------------------+    |
  |                                                                 |
  |    3. Render prompt template                                    |
  |       +--[sandcastle-prompt.md]---------------------------+    |
  |       |  Run: git log -n 5          --> insert commits     |    |
  |       |  Replace: {{ INPUTS }}      --> insert issues      |    |
  |       |  Run: cat ralph/prompt.md   --> insert instructions|    |
  |       +---------------------------------------------------+    |
  |                                                                 |
  |    4. Run Claude Code with rendered prompt                      |
  |       +--[claude-sonnet-4-6]------------------------------+    |
  |       |  Reads issues, picks one, implements, commits      |    |
  |       +---------------------------------------------------+    |
  |                                                                 |
  |    5. Check output for completionSignal                         |
  |       "<promise>NO MORE TASKS</promise>" found?                |
  |         yes --> break loop                                      |
  |         no  --> destroy container, next iteration               |
  |                                                                 |
  +----------------------------------------------------------------+
```

---

## Comparison: Ralph vs Sandcastle

```
  Ralph afk.sh (120 lines of bash):
  - Manually builds the prompt string
  - Manually runs docker run
  - Manually parses JSON output with jq
  - Manually checks for NO MORE TASKS

  Sandcastle main.ts (21 lines of TypeScript):
  - Declaratively configures the same behavior
  - Sandcastle library handles all the plumbing
  - Same result, much less code
```

```
  Ralph:     "Here's exactly HOW to do each step"   (imperative)
  Sandcastle: "Here's WHAT I want to happen"          (declarative)
```
