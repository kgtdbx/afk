# What is `pnpm install --frozen-lockfile`?

## One-Line Answer

"Install exactly what's in the lockfile. If anything doesn't match, FAIL instead of updating."

---

## Background: What's a Lockfile?

When you run `pnpm install`, it creates `pnpm-lock.yaml`:

```
  package.json (what you want):       pnpm-lock.yaml (what you got):
  ============================        ==============================

  "dependencies": {                   express@4.21.2
    "express": "^4.21.0"                resolved: https://registry...
  }                                     integrity: sha512-abc123...
                                        dependencies:
  "^4.21.0" means "4.21.0 or              accepts@1.3.8
  newer, but below 5.0.0"                 body-parser@1.20.3
                                           ...exact versions of everything
```

The lockfile pins EXACT versions of every package and sub-package.

---

## `pnpm install` vs `pnpm install --frozen-lockfile`

```
  pnpm install
  ============
  1. Read package.json
  2. Read pnpm-lock.yaml
  3. If they disagree, UPDATE the lockfile  <-- this is the problem
  4. Install packages

  pnpm install --frozen-lockfile
  ==============================
  1. Read package.json
  2. Read pnpm-lock.yaml
  3. If they disagree, FAIL with an error   <-- safe!
  4. Install packages (only if lockfile matches)
```

---

## Why `--frozen-lockfile` in Ralph?

```
  Without --frozen-lockfile:
  ==========================

  You: "Ralph, work on issue #3"
  Ralph: *runs pnpm install*
  Ralph: *pnpm updates 47 packages because versions drifted*
  Ralph: *commits the changes including a modified pnpm-lock.yaml*
  You: "Wait, I didn't ask you to update dependencies!"

  With --frozen-lockfile:
  =======================

  You: "Ralph, work on issue #3"
  Ralph: *runs pnpm install --frozen-lockfile*
  Ralph: *installs exactly the versions you already locked*
  Ralph: *no surprise dependency changes*
```

It prevents Ralph from accidentally changing your dependency tree while
you're AFK. The lockfile stays exactly as you committed it.

---

## Visual

```
  --frozen-lockfile = "READ-ONLY mode for the lockfile"

  +-------------------+
  |  pnpm-lock.yaml   |
  |  (your versions)  |
  |                   |
  |  express@4.21.2   |----> Install these exact versions
  |  react@19.1.0     |     (no updates, no changes)
  |  drizzle@0.38.3   |
  +-------------------+
         |
         v
  Package versions don't match?
         |
    +----+----+
    |         |
  without   with
  flag      --frozen-lockfile
    |         |
    v         v
  Update    CRASH
  lockfile  (error)
  (risky)   (safe)
```
