# High Level Workflows

All discovered workflows from studying matt-latest, matt-cohort3, matt-previous, and cohort3-project skills.

## Table of Contents

- [Quick Reference: Skill Evolution](#quick-reference-skill-evolution)
- [WORKFLOW 1: Feature Development (HITL → AFK)](#workflow-1-feature-development-hitl--afk)
- [WORKFLOW 2: Bug Triage & Diagnosis](#workflow-2-bug-triage--diagnosis-new)
- [WORKFLOW 3: Architecture Improvement](#workflow-3-architecture-improvement)
- [WORKFLOW 4: Domain Modeling](#workflow-4-domain-modeling-new)
  - [Architecture Decision Records (ADRs)](#architecture-decision-records-adrs)
- [WORKFLOW 5: Prototyping](#workflow-5-prototyping-new)
- [WORKFLOW 6: TDD (Test-Driven Development)](#workflow-6-tdd-test-driven-development)
- [WORKFLOW 7: Token Compression](#workflow-7-token-compression-new)
- [WORKFLOW 8: Agent Handoff](#workflow-8-agent-handoff-new-in-progress)
- [WORKFLOW 9: Code Migration](#workflow-9-code-migration-for-existing-codebases)
- [WORKFLOW 10: Research → Implementation](#workflow-10-research--implementation-pipeline)
- [Skill Comparison: Which Version to Use?](#skill-comparison-which-version-to-use)
- [Cheat Sheet](#cheat-sheet)

---

## Quick Reference: Skill Evolution

```
matt-cohort3 (flat, 19 skills)     →    matt-latest (bucketed, 23 skills)
─────────────────────────────      →    ──────────────────────────────────
/write-a-prd                       →    /to-prd (no interview, synthesize)
/prd-to-plan                       →    REMOVED (absorbed into /to-issues)
/prd-to-issues                     →    /to-issues (vertical slices)
/grill-me                          →    /grill-me (unchanged)
                                   →    /grill-with-docs (NEW — updates CONTEXT.md + ADRs)
/tdd                               →    /tdd (same philosophy, better docs)
                                   →    /diagnose (NEW — structured bug hunting)
                                   →    /prototype (NEW — logic or UI)
                                   →    /caveman (NEW — token compression)
                                   →    /zoom-out (NEW — abstraction navigation)
                                   →    /setup-matt-pocock-skills (NEW — per-repo init)
                                   →    /handoff (NEW — agent-to-agent context transfer)
/github-triage                     →    /triage (expanded state machine)
/triage-issue                      →    merged into /triage + /diagnose
/improve-codebase-architecture     →    /improve-codebase-architecture (now uses CONTEXT.md)
/design-an-interface               →    DEPRECATED
/qa                                →    DEPRECATED
/request-refactor-plan             →    DEPRECATED
/ubiquitous-language               →    DEPRECATED (absorbed into /grill-with-docs)
```

---

## WORKFLOW 1: Feature Development (HITL → AFK)

The main workflow. Human designs, agent builds.

```
┌─────────────────────────────────────────────────────────────┐
│  HITL PHASE (you + Claude interactively)                     │
│                                                              │
│  1. /grill-me "I want <feature idea>"                        │
│     └── Claude interviews you relentlessly until              │
│         shared understanding is reached                      │
│                                                              │
│  2. /grill-with-docs (optional, NEW)                         │
│     └── Stress-test idea against domain model                │
│     └── Updates CONTEXT.md with new terms                    │
│     └── Creates ADRs for hard-to-reverse decisions           │
│                                                              │
│  3. /to-prd (NEW, replaces /write-a-prd)                     │
│     └── Synthesizes conversation into PRD                    │
│     └── No interview — uses what was already discussed       │
│                                                              │
│  4. /prototype (optional, NEW)                               │
│     └── LOGIC: terminal app state machine                    │
│     └── UI: 3+ radically different UI variations             │
│     └── /do-work @plans/plan.md "build prototype on          │
│         throwaway route, dev-only"                           │
│                                                              │
│  5. /to-issues <PRD> (replaces /prd-to-issues)               │
│     └── Breaks PRD into vertical slices (tracer bullets)     │
│     └── Creates GitHub issues with dependency graph          │
│     └── Adds final QA issue blocked by all others            │
│                                                              │
│  6. Review issues, adjust, approve                           │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  AFK PHASE (Ralph runs autonomously)                         │
│                                                              │
│  ./afk/sandcastle/afk.sh 10                                  │
│     └── Picks issues by priority                             │
│     └── Implements one per iteration                         │
│     └── Runs tests + typecheck                               │
│     └── Commits + closes issue                               │
│     └── Repeats until NO MORE TASKS                          │
│                                                              │
│  IMPORTANT: Add to prompt.md:                                │
│  "Use red/green/refactor TDD for backend code"               │
│  Otherwise Ralph writes code first, tests after.             │
└──────────────────────────┬──────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│  REVIEW PHASE (you verify)                                   │
│                                                              │
│  git log                   (see what Ralph committed)        │
│  npm run dev               (manual QA)                       │
│  pnpm test                 (verify tests pass)               │
└─────────────────────────────────────────────────────────────┘
```

### OLD workflow (cohort3):
```
/grill-me → /write-a-prd → /prd-to-plan → "do phase N" manually → repeat
```

### NEW workflow (matt-latest):
```
/grill-with-docs → /to-prd → /to-issues → AFK
```

Key difference: OLD had a plan file with phases you executed one by one. NEW creates GitHub issues with dependencies and lets Ralph work through them autonomously.

---

## WORKFLOW 2: Bug Triage & Diagnosis (NEW)

Didn't exist in cohort3. Two new skills work together.

```
Bug report arrives
       │
       ▼
┌──────────────────┐     ┌──────────────────────────────────┐
│  /triage          │     │  5 states:                        │
│                   │     │  needs-triage → needs-info         │
│  Evaluate issue   │────►│  needs-info → ready-for-agent     │
│  Assign state     │     │  ready-for-agent → (AFK builds)   │
│  Add labels       │     │  ready-for-human → (HITL needed)  │
│                   │     │  wontfix → close                  │
└──────────────────┘     └──────────────────────────────────┘
       │
       │ if bug needs diagnosis
       ▼
┌──────────────────────────────────────────────────────────────┐
│  /diagnose                                                    │
│                                                               │
│  1. REPRODUCE — get a fast, deterministic repro               │
│     (2-second loop >> flaky 30-second loop)                   │
│                                                               │
│  2. MINIMISE — strip to smallest failing case                 │
│                                                               │
│  3. HYPOTHESISE — form theory about root cause                │
│                                                               │
│  4. INSTRUMENT — add logging/assertions to verify             │
│                                                               │
│  5. FIX — minimal change                                      │
│                                                               │
│  6. REGRESSION TEST — write test that would have caught it    │
│                                                               │
│  If architecture issues found → /improve-codebase-architecture│
└──────────────────────────────────────────────────────────────┘
```

---

## WORKFLOW 3: Architecture Improvement
(Improve/refactor codebase structure: walks through the codebase and finds opportunities to deepen it)

Same skill, but matt-latest adds domain awareness.

```
/improve-codebase-architecture
       │
       ├── Explore codebase (Agent subagent)
       │   Now also reads CONTEXT.md for domain vocabulary
       │   and docs/adr/ for existing decisions
       │
       ├── Present candidates (numbered list)
       │   User picks one
       │
       ├── Design interfaces (3+ sub-agents in parallel)
       │   Each with a different constraint:
       │   - Minimize interface (1-3 entry points)
       │   - Maximize flexibility
       │   - Optimize for common caller
       │   - Ports & adapters (if cross-boundary)
       │
       ├── Compare, recommend, user picks
       │
       └── Create GitHub issue RFC
           └── /to-issues to break RFC into slices
           └── AFK implements
```

### Critical: Use TDD when AFK refactors

```
⚠️  ATTENTION! SPECIFY THAT YOU WANT red/green/refactor WHEN AFK.
    Ralph wrote all the code first, then added tests after —
    the opposite of TDD. This led to 8 tests covering dead code
    (completeLessonGamification) that we had to revert because
    it broke the app. If Ralph had used TDD, the first test cycle
    would have caught the bundling issue before committing.

    Two ways to enforce TDD:

    Option A: Add to ralph/prompt.md (applies to all AFK runs):
    "Use red-green-refactor TDD for all backend changes.
     Write ONE failing test, then minimal code to pass, repeat."

    Option B: Pass directly when running a skill (one-off):
    /improve-codebase-architecture Use red-green-refactor TDD
     for all backend changes. Write ONE failing test, then
     minimal code to pass, repeat.
```

### Debugging: Playwright MCP + git bisect by hand

When the refactoring broke the app (client-side navigation died),
Playwright MCP was critical to finding the exact bug:

```
1. Playwright MCP let the LLM see the actual browser state —
   console errors, DOM snapshots, page URLs after navigation.
   Screenshots alone weren't enough. The LLM needed to read
   "TypeError: promisify is not a function" from the console
   to understand better-sqlite3 was leaking into the client.

2. We peeled back commits one by one to isolate the problem:
   - Revert ALL Ralph's changes → app works
   - Restore gamificationService.ts only → still works
   - Restore layout.app.tsx → still works
   - Restore dashboard.tsx → still works
   - Restore lesson route → BREAKS
   Found: the lesson route import was the culprit.

3. After fixing the root cause (reverted lesson route, moved
   cross-service functions to .server.ts), we invoked /tdd to
   write integration tests on top of the now-working code:
   /tdd Write integration tests for the mark-complete action
   This ensured the fix was covered by tests before moving on.

4. Setup: claude mcp add playwright npx @playwright/mcp@latest
   Then restart Claude Code session to pick it up.
```

### What we learned from our refactoring:

```
⚠️  WATCH OUT: React Router bundles route imports for
    both server and client. Adding cross-service imports
    to a file that routes import can break the client.

⚠️  .server.ts suffix does NOT protect route imports.

⚠️  Always test with npm run dev after refactoring,
    not just pnpm test + typecheck.
```

---

## WORKFLOW 4: Domain Modeling (NEW)

Didn't exist in cohort3. Builds shared vocabulary.

```
┌──────────────────────────────────────────────────────────────┐
│  /setup-matt-pocock-skills (run once per repo)                │
│                                                               │
│  Creates:                                                     │
│  ├── docs/agents/domain.md      (domain glossary)             │
│  ├── docs/agents/issue-tracker.md (GitHub/GitLab/local)       │
│  └── docs/agents/triage-labels.md (label definitions)         │
│                                                               │
│  All other skills read from these files.                      │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  /grill-with-docs (run during design sessions)                │
│                                                               │
│  Like /grill-me but also:                                     │
│  - Updates CONTEXT.md when new terms crystallize              │
│  - Creates ADRs when hard-to-reverse decisions are made       │
│  - Writes to docs/adr/ using standard ADR format              │
│                                                               │
│  Result: domain vocabulary grows over time.                   │
│  AI agents navigate code faster with shared language.         │
└──────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────┐
│  /zoom-out (run anytime)                                      │
│                                                               │
│  "Show me the bigger picture"                                 │
│  Uses domain glossary to describe system at a higher          │
│  abstraction level. Useful when you're lost in details.       │
└──────────────────────────────────────────────────────────────┘
```

### Architecture Decision Records (ADRs)

ADRs are short documents that record *why* a decision was made. They live in `docs/adr/` and are created by `/grill-with-docs` when a decision meets all three criteria:

1. **Hard to reverse** — changing your mind later is costly
2. **Surprising without context** — a future reader would wonder "why?"
3. **Real trade-off** — genuine alternatives existed

```
docs/adr/
├── 0001-explicit-setup-pointer-only-for-hard-dependencies.md
├── 0002-event-sourced-write-model.md
└── 0003-manual-sql-over-orm.md
```

**Format** — can be as short as one paragraph:
```markdown
# {Short title of the decision}

{1-3 sentences: what's the context, what did we decide, and why.}
```

**Optional sections** (only when they add genuine value):
- **Status** — `proposed | accepted | deprecated | superseded by ADR-NNNN`
- **Considered Options** — only when rejected alternatives are worth remembering
- **Consequences** — only when non-obvious downstream effects exist

**What qualifies:**
- Architectural shape ("monorepo", "event-sourced write model")
- Integration patterns between contexts ("events, not synchronous HTTP")
- Technology choices with lock-in (database, auth provider, deploy target)
- Boundary/scope decisions ("Customer context owns customer data")
- Deliberate deviations from the obvious ("manual SQL because X")
- Constraints not visible in code ("can't use AWS — compliance")
- Rejected alternatives when non-obvious ("considered GraphQL, picked REST because X")

**What doesn't qualify:**
- Easy to reverse — just reverse it
- Not surprising — nobody will wonder
- No real alternative — nothing to record

**How they're used:**
- `/improve-codebase-architecture` reads ADRs to avoid contradicting past decisions
- `/grill-with-docs` creates new ADRs during design sessions
- `/tdd` and `/diagnose` reference ADRs as soft context (degrade gracefully without them)
- Future agents read them to understand *why*, not just *what*

---

## WORKFLOW 5: Prototyping (NEW)

Two branches depending on what you're validating.

```
/prototype
    │
    ├── LOGIC branch
    │   "Build a terminal app that simulates the state machine"
    │   - No UI, just the logic
    │   - Proves the algorithm works
    │   - Can be thrown away or extracted
    │
    └── UI branch
        "Design 3+ radically different UI approaches"
        - Each variation is a separate component
        - User picks one, others are deleted
        - Validates the UX before committing
```

### How we used it:
```
/do-work @plans/live-presence-indicator.md
  "build a prototype on a throwaway route, dev-only"

Result: /dev/presence route with working Ably presence
        Reusable: PresencePill, PresenceIndicator components
```

---

## WORKFLOW 6: TDD (Test-Driven Development)

Test-Driven Development means writing the test **before** the code. The test defines what "done" looks like, then you write the minimum code to make it pass.

### The Red-Green-Refactor Loop

```
┌─────────────────────────────────────────────────────────────┐
│                                                              │
│  RED    → Write ONE test that describes a behavior           │
│           Run it. It MUST fail. (If it passes, the test      │
│           is testing nothing.)                               │
│                                                              │
│  GREEN  → Write the MINIMUM code to make the test pass.      │
│           No more. Don't anticipate future tests.            │
│                                                              │
│  REFACTOR → Clean up while tests stay green.                 │
│             Extract duplication, deepen modules,             │
│             improve names. Never refactor while RED.         │
│                                                              │
│  Repeat with the next behavior.                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Anti-Pattern: Horizontal Slicing

```
WRONG (horizontal — write all tests, then all code):
  RED:   test1, test2, test3, test4, test5
  GREEN: impl1, impl2, impl3, impl4, impl5

  This produces CRAP TESTS because:
  - Tests are written against imagined behavior, not actual
  - You test the shape of things (data structures) not behavior
  - Tests become insensitive to real changes
  - You outrun your headlights

RIGHT (vertical — one test, one implementation, repeat):
  RED→GREEN: test1→impl1
  RED→GREEN: test2→impl2
  RED→GREEN: test3→impl3

  Each test responds to what you learned from the previous cycle.
```

### Good Tests vs Bad Tests

```
GOOD — tests observable behavior through public interface:

  test("completing a lesson awards 10 XP", () => {
    awardXp(userId, 10, "lesson", lessonId);
    expect(getTotalXp(userId)).toBe(10);
  });

  test("createUser makes user retrievable", () => {
    const user = createUser({ name: "Alice" });
    const retrieved = getUser(user.id);
    expect(retrieved.name).toBe("Alice");
  });

  Characteristics:
  ✓ Tests what users/callers care about
  ✓ Uses public API only
  ✓ Survives internal refactors
  ✓ Describes WHAT, not HOW

BAD — coupled to implementation details:

  test("checkout calls paymentService.process", () => {
    const mockPayment = jest.mock(paymentService);
    checkout(cart, payment);
    expect(mockPayment.process).toHaveBeenCalledWith(cart.total);
  });

  test("createUser saves to database", () => {
    createUser({ name: "Alice" });
    const row = db.query("SELECT * FROM users WHERE name = ?", ["Alice"]);
    expect(row).toBeDefined();  // bypasses interface!
  });

  Red flags:
  ✗ Mocking internal collaborators (not system boundaries)
  ✗ Testing private methods
  ✗ Asserting on call counts/order
  ✗ Test breaks on refactor without behavior change
  ✗ Verifying through DB queries instead of interface
```

### When to Mock

```
MOCK at system boundaries only:
  ✓ External APIs (Stripe, Ably, email)
  ✓ Time / randomness (vi.useFakeTimers)
  ✓ File system (when necessary)

DON'T mock your own code:
  ✗ Your own classes/modules
  ✗ Internal collaborators
  ✗ Anything you control

Design for mockability:
  // GOOD — dependency injected, easy to mock
  function processPayment(order, paymentClient) {
    return paymentClient.charge(order.total);
  }

  // BAD — creates dependency internally, hard to mock
  function processPayment(order) {
    const client = new StripeClient(process.env.STRIPE_KEY);
    return client.charge(order.total);
  }
```

### Interface Design for Testability

```
1. Accept dependencies, don't create them
   function processOrder(order, paymentGateway) {}     ✓
   function processOrder(order) { new Stripe() }       ✗

2. Return results, don't produce side effects
   function calculateDiscount(cart): Discount {}        ✓
   function applyDiscount(cart): void { cart.total -= } ✗

3. Small surface area
   Fewer methods = fewer tests needed
   Fewer params = simpler test setup
```

### Refactor Candidates (after GREEN)

After all tests pass, look for:
- **Duplication** → extract function
- **Long methods** → break into private helpers (keep tests on public interface)
- **Shallow modules** → combine or deepen
- **Feature envy** → move logic to where data lives
- **Primitive obsession** → introduce value objects
- **Existing code** the new code reveals as problematic

### Usage Examples

**Build a new feature with TDD:**
```
/tdd Build the gamification XP award system. When a student
completes a lesson, they earn 10 XP. Duplicate completions
should not award extra XP.
```

**Write integration tests for existing untested code:**
```
/tdd Write integration tests for the mark-complete action in
courses.$slug.lessons.$lessonId.tsx — test that completing a
lesson awards XP, records streak, and detects module completion.
Test through the service interface, not the route.
```

**Add tests during a refactoring:**
```
/tdd I'm about to refactor the analytics service to deduplicate
instructor/admin functions. Write boundary tests first so I
know the refactor doesn't break anything.
```

**Fix a bug with TDD (write failing test first):**
```
/tdd The streak counter doesn't reset when a user skips a day.
Write a failing test that demonstrates the bug, then fix it.
```

**Test a complex workflow end-to-end:**
```
/tdd Write integration tests for the purchase flow:
user buys course → enrollment created → team coupons generated
→ notification sent to instructor. Test through service
interfaces, not route handlers.
```

**Use with AFK (add to prompt.md):**
```
When implementing backend code, use red-green-refactor TDD:
1. Write ONE failing test for the smallest behavior
2. Write minimal code to make it pass
3. Repeat for the next behavior
Do NOT write all tests first then all implementation.
Do NOT write implementation without a failing test first.
```

### What We Learned

```
⚠️  Ralph doesn't do TDD by default. He writes all code
    first, then adds tests after. You must explicitly
    instruct TDD in the prompt.

⚠️  When using /do-work, it says "use TDD for backend"
    but Ralph still does code-first. /tdd is more explicit.

⚠️  Tests that test dead code are worthless. We wrote 8
    tests for completeLessonGamification — then reverted
    the function because it broke the app. Those tests
    tested nothing.

✓   Tests written AFTER understanding the code (via TDD
    vertical slices) are better than tests written upfront
    against imagined behavior.
```

---

## WORKFLOW 7: Token Compression (NEW)

```
/caveman

Activates ultra-compressed communication for the rest
of the session. ~75% token reduction.

Before: "I've analyzed the codebase and identified several
         areas where we could improve the architecture..."

After:  "found 3 arch issues: 1) analytics dupe 2) route
         god-object 3) enrollment side-effects. which?"

Use when:
- Long sessions approaching context limit
- Rapid iteration where verbosity slows you down
- You know what you want and just need execution
```

---

## WORKFLOW 8: Agent Handoff (NEW, in-progress)

```
/handoff

Compacts the current conversation into a handoff document
that another agent session can pick up. Includes:
- What was done
- What remains
- Key decisions made
- Files modified
- Gotchas discovered

Use when:
- Context window is getting full
- Switching from HITL to AFK
- Passing work between team members
```

---

## WORKFLOW 9: Code Migration (for existing codebases)

When bringing AI into a codebase that has no tests, no docs, no domain model.

```
Step 1: Understand
  /zoom-out
  /grill-with-docs (builds CONTEXT.md from scratch)

Step 2: Document decisions
  /grill-with-docs (creates ADRs for existing architecture)

Step 3: Improve structure
  /improve-codebase-architecture
  (you need good architecture before tests are useful)

Step 4: Introduce testing
  /tdd (adds tests to the now-improved architecture)

Step 5: Ongoing development
  Use the standard feature workflow (Workflow 1)
```

---

## WORKFLOW 10: Research → Implementation Pipeline

```
1. Research (freeform)
   - Explore options, read docs, compare approaches
   - Store findings in plans/research-<topic>.md
   - "This helps LLMs think less" — pre-digested context

2. PRD
   /to-prd (synthesize research into requirements)

3. Prototype (optional)
   /do-work "build throwaway prototype on dev route"

4. Issues
   /to-issues <PRD>

5. Build
   AFK or /tdd
```

---

## Skill Comparison: Which Version to Use?

| Workflow | matt-cohort3 | matt-previous | matt-latest |
|----------|:---:|:---:|:---:|
| Feature dev (PRD → issues → AFK) | Partial | Partial | Full |
| Bug triage + diagnosis | No | No | Yes |
| Domain modeling (CONTEXT.md + ADRs) | No | Partial | Yes |
| Prototyping (logic + UI) | No | No | Yes |
| Token compression | No | Yes | Yes |
| Zoom out / abstraction | No | Yes | Yes |
| Agent handoff | No | No | In progress |
| Per-repo setup | No | No | Yes |
| TDD | Yes | Yes | Yes (better docs) |
| Architecture improvement | Yes | Yes | Yes (domain-aware) |

**Recommendation:** Use **matt-latest** for the full workflow. Install cohort3-project skills (`do-work`, `better-sqlite3-rebuild`, `pnpm-not-found`) alongside since they're project-specific utilities matt-latest doesn't cover.

---

## Cheat Sheet

```bash
# === HITL (interactive with Claude) ===
/grill-me "feature idea"              # brainstorm
/grill-with-docs                      # stress-test against domain
/to-prd                               # synthesize to PRD
/prototype                            # validate design
/to-issues #<prd-issue>               # break into slices
/tdd "build <thing>"                  # red-green-refactor
/diagnose                             # structured bug hunting
/improve-codebase-architecture        # find deepening opportunities
/zoom-out                             # see the bigger picture
/caveman                              # compress tokens
/handoff                              # pass to next agent

# === AFK — Sandcastle ===
./afk/sandcastle/afk.sh 100                                           # all open issues
./afk/sandcastle/afk.sh 100 --issue 1                                 # one issue
./afk/sandcastle/afk.sh 100 --issue 1 --issue 2                       # multiple issues
./afk/sandcastle/afk.sh 100 --file plans/prd.md                       # one file
./afk/sandcastle/afk.sh 100 --file plans/plan.md --file plans/prd.md  # multiple files
./afk/sandcastle/afk.sh 100 --issue 1 --file plans/prd.md             # mix issues + files

# === AFK — Ralph (Docker) ===
./afk/ralph/afk.sh 100                                             # all open issues
./afk/ralph/afk.sh 100 --issue 1                                   # one issue
./afk/ralph/afk.sh 100 --issue 1 --issue 2                         # multiple issues
./afk/ralph/afk.sh 100 --file plans/prd.md                         # one file
./afk/ralph/afk.sh 100 --file plans/plan.md --file plans/prd.md    # multiple files
./afk/ralph/afk.sh 100 --issue 1 --file plans/prd.md               # mix issues + files

# === Utilities ===
/do-work @plans/plan.md               # end-to-end implementation
/setup-matt-pocock-skills             # initialize repo config
npm run dev                           # run the app
pnpm test                             # run tests
pnpm typecheck                        # type check
```
