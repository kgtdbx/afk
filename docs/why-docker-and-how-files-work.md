# Why Docker? And How Do Files Work?

## Why Docker for AFK development?

### The Problem

```
  Claude Code can run ANY command on your machine:
    rm -rf /
    git push --force
    drop database production

  You're AFK (away from keyboard).
  Nobody is watching.
  Nobody can click "deny" on a dangerous command.
```

### The Solution: Sandbox

```
  +--[Your Mac]------------------------------------------+
  |                                                       |
  |  Your files, your system, your everything             |
  |                                                       |
  |  +--[Docker Container]----------------------------+   |
  |  |                                                 |   |
  |  |  Claude runs HERE, isolated.                    |   |
  |  |                                                 |   |
  |  |  - Can only see /workspace (your project)       |   |
  |  |  - Can't access your home directory             |   |
  |  |  - Can't access other projects                  |   |
  |  |  - Can't install system-wide software           |   |
  |  |  - If it goes haywire, just kill the container  |   |
  |  |                                                 |   |
  |  +-------------------------------------------------+   |
  |                                                       |
  +-------------------------------------------------------+
```

Docker provides **isolation**. It's a lightweight virtual machine that
contains the blast radius of whatever Claude does.

---

## How Do File Changes Work? (Bind Mounts)

### The Key Line

```bash
docker run -v "$PROJECT_DIR":/workspace ...
```

The `-v` flag creates a **bind mount**:

```
  Your Mac filesystem              Docker container filesystem
  ==================               ============================

  /Users/krl/Documents/            /workspace/
    dev/cohort-003-project/           (same files!)
      src/                              src/
        app.ts                            app.ts    <-- SAME file
      package.json                      package.json <-- SAME file
      README.md                         README.md    <-- SAME file
```

### It's NOT a copy. It's a window.

```
  +--[Your Mac's disk]-----------------------------------+
  |                                                       |
  |  /Users/krl/.../cohort-003-project/                  |
  |    |                                                  |
  |    +-- src/app.ts  <-- THE ACTUAL FILE                |
  |         ^                                             |
  |         |                                             |
  |    +----+----+                                        |
  |    |         |                                        |
  |  You see   Docker sees                                |
  |  it here   it here                                    |
  |  (Mac)     (/workspace)                               |
  |                                                       |
  +-------------------------------------------------------+
```

When Claude edits `/workspace/src/app.ts` inside Docker, it's editing
your actual file. **Changes are instant and permanent.** There's no
"pulling" or "putting back."

### What about node_modules?

```bash
-v ralph_node_modules:/workspace/node_modules
```

This is different -- it's a **named volume**, not a bind mount:

```
  Your Mac's node_modules/     Docker's node_modules/
  =========================    =======================
  Contains macOS binaries      Contains Linux binaries
  (arm64-darwin)               (x64-linux)

  These are SEPARATE. Docker has its own copy.
  Your Mac's node_modules is hidden ("masked") inside the container.
```

Why? Because native modules (like `better-sqlite3`) compile platform-specific
binaries. macOS binaries crash on Linux and vice versa.

---

## macOS vs Linux: How Does It Affect the Workflow?

```
  Your Mac (macOS, ARM64)          Docker Container (Linux, x64)
  =========================        ==============================

  Source code: shared via           Source code: sees the same files
  bind mount (read/write)          at /workspace

  node_modules: your Mac's         node_modules: Linux-compiled
  version (macOS binaries)         version (in named volume)

  git: your Mac's git              git: Linux git (in container)
  (same .git folder, shared)       (operates on the same repo)

  Claude Code: not running         Claude Code: running HERE
  on Mac during AFK                inside the container
```

### Potential issues and how they're handled:

```
  Issue: Native modules (better-sqlite3, rollup) are platform-specific
  Fix:   Named volume for node_modules + pnpm rebuild inside container

  Issue: File permissions differ between macOS and Linux
  Fix:   Dockerfile sets UID/GID to match macOS user (503:20)
         (see Dockerfile line: usermod -u 503 -g 20)

  Issue: Line endings (CR vs LF)
  Fix:   Not an issue here -- macOS and Linux both use LF
```

---

## Internet Access from Docker

**Yes, Docker containers have internet access by default.**

Claude uses the internet inside the container for:

```
  +--[Container]--------------------------------------------+
  |                                                          |
  |  Internet-dependent operations:                          |
  |                                                          |
  |  1. claude --print             Calls Claude API          |
  |     (talks to api.anthropic.com)                         |
  |                                                          |
  |  2. gh issue view              Fetches from GitHub API   |
  |     gh issue close             Posts to GitHub API       |
  |                                                          |
  |  3. pnpm install               Downloads npm packages    |
  |     (only if lockfile changed)                           |
  |                                                          |
  |  Local-only operations:                                  |
  |                                                          |
  |  4. Read/write source code     Local filesystem          |
  |  5. git commit                 Local .git directory      |
  |  6. pnpm test                  Runs locally              |
  |  7. pnpm typecheck             Runs locally              |
  |                                                          |
  +----------------------------------------------------------+
```

---

## What Happens If Docker Terminates Abruptly?

### Scenario: Container crashes mid-work

```
  Timeline:
  =========

  1. Container starts
  2. Claude reads issue #3
  3. Claude edits src/app.ts        <-- file CHANGED on your Mac
  4. Claude edits src/db.ts         <-- file CHANGED on your Mac
  5. *** CRASH / KILL / POWER OUT ***
  6. Claude never ran tests
  7. Claude never committed
  8. Claude never closed the issue
```

### What's left behind:

```
  +--[Your Mac after crash]----------------------------------+
  |                                                           |
  |  src/app.ts    --> MODIFIED (Claude's partial changes)    |
  |  src/db.ts     --> MODIFIED (Claude's partial changes)    |
  |  .git/         --> NO NEW COMMIT (Claude didn't get to it)|
  |  GitHub #3     --> STILL OPEN (Claude didn't close it)    |
  |                                                           |
  |  You have UNCOMMITTED, POTENTIALLY INCOMPLETE changes.    |
  |                                                           |
  +-----------------------------------------------------------+
```

### How to recover:

```
  Option A: Inspect and keep the changes
  $ git diff                   # See what Claude changed
  $ git add -A && git commit   # If the changes look good

  Option B: Throw away the changes
  $ git checkout .             # Revert all uncommitted changes

  Option C: Just re-run afk.sh
  - The issue is still open (Claude didn't close it)
  - Next iteration will pick it up again
  - It will see uncommitted changes and may continue from there
    or start fresh
```

### Key insight: the bind mount is a double-edged sword

```
  GOOD: Changes persist even if the container dies.
        Git commits survive because .git is on your Mac.

  BAD:  Partial/broken changes also persist.
        No automatic rollback on crash.

  This is why Claude commits AFTER testing:

  Edit files --> Run tests --> Commit (atomic save point)
                    |
                    v
              If crash happens before commit,
              you lose work but the repo is clean.
              If crash happens after commit,
              the work is safely saved.
```

### The `--rm` flag and crashes:

```
  Normal exit:    container runs --> finishes --> --rm destroys it
  Crash/kill:     container runs --> dies     --> --rm STILL destroys it
  docker kill:    you force-kill  --> --rm STILL destroys it

  --rm means "clean up the container no matter what."
  It does NOT affect the bind-mounted files (those are on your Mac).
```

---

## Summary

| Question | Answer |
|----------|--------|
| Why Docker? | Isolation. Claude can't damage your system, only the project files. |
| Are files copied into Docker? | No. Bind mount = same files, shared in real-time. |
| Do changes survive container death? | Yes. Files are on your Mac's disk, not in the container. |
| What about node_modules? | Separate Linux copy in a named Docker volume. |
| Does Docker have internet? | Yes, by default. Used for Claude API, GitHub API, npm. |
| What if Docker crashes mid-work? | Uncommitted file changes remain. No git commit = no save point. Run `git diff` to inspect, `git checkout .` to discard. |
| macOS vs Linux issues? | Handled by UID matching + separate node_modules volume. |
