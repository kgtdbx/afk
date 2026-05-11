# How the Backlog Queue & Context Flow Between Iterations

## TL;DR

There is **no shared memory between iterations**. Each iteration is a fresh
Claude session. The "backlog" is re-fetched from GitHub (or files) every time.
Context is never explicitly cleared because it is never carried over.

---

## 1. The Loop: Each Iteration is a Clean Slate

### Ralph (Docker) - `ralph/afk.sh`

```
  afk.sh 5
    |
    v
 for i in 1..5                 <-- outer bash loop
    |
    |   +--------------------------------------------------+
    |   |  docker run --rm ...                             |
    |   |    claude --print "$RALPH_PROMPT"                 |
    |   |                                                  |
    |   |  This is a ONE-SHOT invocation of Claude.        |
    |   |  --print means: run, produce output, exit.       |
    |   |  --rm means: destroy the container after exit.   |
    |   +--------------------------------------------------+
    |                    |
    |                    v
    |            Output includes "<promise>NO MORE TASKS</promise>"?
    |                   / \
    |                 yes   no
    |                 /       \
    |           exit 0     next iteration (i++)
    |                           |
    +---------------------------+
```

### Sandcastle - `sandcastle/main.ts`

```
  afk.sh 5
    |
    v
  npx tsx .sandcastle/main.ts "$inputs" 5
    |
    v
  run({
    sandbox: docker(),            <-- fresh container per iteration
    maxIterations: 5,
    completionSignal: "<promise>NO MORE TASKS</promise>",
    ...
  })
    |
    v
  Sandcastle internally loops 1..maxIterations:
    each iteration = new Claude session inside a new sandbox
```

---

## 2. How the Backlog is Passed Between Tasks

Short answer: **it isn't "passed" -- it's re-read from the source every time.**

```
+==========================================+
|           PERSISTENT STATE               |
|  (survives across all iterations)        |
|                                          |
|  +------------------+  +-------------+  |
|  |  GitHub Issues   |  |  Git Repo   |  |
|  |  (open/closed)   |  |  (commits)  |  |
|  +--------+---------+  +------+------+  |
|           |                    |         |
+===========|====================|=========+
            |                    |
            v                    v
     gh issue list         git log -n 5
            |                    |
            v                    v
    +-------+--------------------+--------+
    |         afk.sh (before each run)    |
    |                                     |
    |   inputs = issue titles + files     |
    |   commits = last 5 git commits      |
    +----------------+--------------------+
                     |
                     v
    +----------------+--------------------+
    |        PROMPT (assembled fresh)     |
    |                                     |
    |  "Previous commits: ..."           |
    |  "Inputs: #1 Add XP, #2 Streaks"  |
    |  "Pick ONE issue. Implement it."   |
    +----------------+--------------------+
                     |
                     v
    +----------------+--------------------+
    |     FRESH CLAUDE SESSION            |
    |     (no memory of prior runs)       |
    |                                     |
    |  1. Reads issue list from prompt    |
    |  2. Picks one issue                 |
    |  3. Fetches full body via gh        |
    |  4. Implements it                   |
    |  5. Commits + closes issue on GH    |
    +-------------------------------------+
```

### The key insight:

```
  Iteration 1                 Iteration 2                 Iteration 3
  =============               =============               =============

  GitHub Issues:              GitHub Issues:              GitHub Issues:
  #1 open                     #1 CLOSED (by iter 1)      #1 closed
  #2 open                     #2 open                     #2 CLOSED (by iter 2)
  #3 open                     #3 open                     #3 open

  Claude picks #1             Claude picks #2             Claude picks #3
  Implements it               Implements it               Implements it
  Closes #1 on GH             Closes #2 on GH             Closes #3 on GH
  Commits to git              Commits to git              Commits to git

       |                           |                           |
       v                           v                           v
  Container destroyed         Container destroyed         Container destroyed
  Context gone                Context gone                Context gone
```

**There is no backlog queue data structure.** GitHub IS the queue. Closing an
issue removes it from the next `gh issue list` call. That's the entire
coordination mechanism.

---

## 3. Data Flow Diagram: What Persists vs. What's Ephemeral

```
+=================================================================+
|                    PERSISTS ACROSS ITERATIONS                   |
|                                                                 |
|   +-------------------+     +-----------------------------+     |
|   |    GitHub Issues   |     |      Git Repository         |     |
|   |                   |     |                             |     |
|   |  - Open issues    |     |  - Committed code           |     |
|   |  - Closed issues  |     |  - Commit messages          |     |
|   |  - Comments       |     |  - Branch state             |     |
|   +-------------------+     +-----------------------------+     |
|                                                                 |
+=================================================================+

+=================================================================+
|                  EPHEMERAL (per iteration)                      |
|                                                                 |
|   +-------------------+     +-----------------------------+     |
|   | Docker Container  |     |    Claude Session           |     |
|   |                   |     |                             |     |
|   | - Filesystem      |     |  - Conversation context     |     |
|   | - Processes       |     |  - Tool call history        |     |
|   | - Env vars        |     |  - Reasoning state          |     |
|   +-------------------+     +-----------------------------+     |
|                                                                 |
|   Created fresh -----> Used once -----> Destroyed               |
|                                                                 |
+=================================================================+
```

---

## 4. When is a New Session/Context Created?

**Every single iteration = a brand new Claude session.**

### Ralph Runner

```
  for ((i=1; i<=$MAX_ITER; i++)); do        # <-- bash loop
      docker run --rm \                       # <-- NEW container
          claude --print "$RALPH_PROMPT"       # <-- NEW Claude session
  done
```

- `docker run --rm` = start container, run command, destroy container
- `claude --print` = one-shot mode (not interactive), exits after response
- No `--resume`, no session ID, no conversation continuation

### Sandcastle Runner

```
  run({
    sandbox: docker(),         # <-- Sandcastle manages the sandbox lifecycle
    maxIterations: 5,          # <-- each iteration = new sandbox + new session
  })
```

Sandcastle's `run()` function internally creates a fresh sandbox (Docker
container) for each iteration of its loop.

---

## 5. Why No Explicit Context Reset?

```
  Q: "We don't explicitly mention clearing or resetting context anywhere"

  A: Because there's nothing to clear.

  +--------------------+
  | Iteration N        |
  | Claude session     |   --rm (container destroyed)
  | starts and ends    |------> GONE. Memory = 0.
  +--------------------+

  +--------------------+
  | Iteration N+1      |
  | Brand new Claude   |   Knows NOTHING about iteration N.
  | session starts     |   Gets fresh prompt with current state.
  +--------------------+
```

The architecture is **stateless by design**:

```
  Stateful approach (NOT how this works):
  =========================================
  Session 1: "Do task A"
  Session 1: "Now do task B"    <-- same context, carries forward
  Session 1: "Now do task C"    <-- context grows, may get confused

  Stateless approach (HOW this actually works):
  =========================================
  Session 1: "Here are all open issues. Pick one. Do it."  --> exits
  Session 2: "Here are all open issues. Pick one. Do it."  --> exits
  Session 3: "Here are all open issues. Pick one. Do it."  --> exits
```

Each session gets the **current world state** (open issues, recent commits)
rather than a history of what previous sessions did.

---

## 6. Coordination Mechanism: GitHub as the Message Bus

```
                         +------------------+
                         |   GitHub Issues   |
                         |   (the "queue")   |
                         +--------+---------+
                                  |
                    +-------------+-------------+
                    |                           |
                    v                           v
             gh issue list                gh issue close
             (read queue)                 (dequeue item)
                    |                           ^
                    v                           |
  +-----------------+---------------------------+------------------+
  |                        afk.sh loop                            |
  |                                                                |
  |   Iter 1: list issues --> pick #3 --> implement --> close #3   |
  |   Iter 2: list issues --> pick #7 --> implement --> close #7   |
  |   Iter 3: list issues --> all closed --> NO MORE TASKS         |
  |                                                                |
  +----------------------------------------------------------------+
```

The `<promise>NO MORE TASKS</promise>` signal is how Claude tells the loop
"the queue is empty -- stop iterating."

---

## 7. Complete End-to-End Flow (Ralph Docker Runner)

```
  Human runs: ./ralph/afk.sh 5

  +--[afk.sh]------------------------------------------+
  |                                                     |
  |  1. Parse args (max_iter=5, issues=[], files=[])    |
  |  2. GH_REPO = parse git remote                     |
  |  3. inputs = gh issue list --state open             |
  |                                                     |
  |  +--[LOOP i=1..5]---------------------------------+ |
  |  |                                                 | |
  |  |  4. commits = git log -n 5                     | |
  |  |  5. prompt = cat prompt.md                     | |
  |  |  6. RALPH_PROMPT = commits + inputs + prompt   | |
  |  |                                                 | |
  |  |  7. docker run --rm ralph-runner               | |
  |  |     +--[CONTAINER]----------------------------+| |
  |  |     |                                         || |
  |  |     |  8. pnpm install --frozen-lockfile       || |
  |  |     |  9. claude --print "$RALPH_PROMPT"       || |
  |  |     |     +--[CLAUDE SESSION]----------------+|| |
  |  |     |     |                                  ||| |
  |  |     |     | 10. Read prompt, see issues      ||| |
  |  |     |     | 11. Pick one issue               ||| |
  |  |     |     | 12. gh issue view <num>          ||| |
  |  |     |     | 13. Explore codebase             ||| |
  |  |     |     | 14. Implement changes            ||| |
  |  |     |     | 15. pnpm test + typecheck        ||| |
  |  |     |     | 16. git commit                   ||| |
  |  |     |     | 17. gh issue close <num>         ||| |
  |  |     |     |                                  ||| |
  |  |     |     +----------------------------------+|| |
  |  |     |                                         || |
  |  |     +--(container destroyed)------------------+| |
  |  |                                                 | |
  |  |  18. Check output for NO MORE TASKS             | |
  |  |      yes --> exit 0                             | |
  |  |      no  --> continue loop                      | |
  |  |                                                 | |
  |  +-------------------------------------------------+ |
  |                                                     |
  +-----------------------------------------------------+
```

---

## Summary Table

| Question | Answer |
|----------|--------|
| How is the backlog passed between tasks? | It isn't. GitHub Issues are re-fetched each iteration via `gh issue list`. |
| How do we know a new context is created? | Every `docker run --rm` + `claude --print` = new container + new session. |
| Where is context cleared/reset? | Nowhere explicitly. The container is destroyed (`--rm`), taking all state with it. |
| What persists between iterations? | Only Git (commits) and GitHub (issue open/closed state). |
| What coordinates the work? | GitHub Issues act as the queue. Closing an issue = dequeuing it. |
| How does the loop stop? | Claude outputs `<promise>NO MORE TASKS</promise>` when all issues are done. |
