# npx vs npm

## One-Line Answer

- `npm install` = **install** packages
- `npx some-command` = **run** a package's binary (without installing it globally)

---

## npm (Node Package Manager)

```
  npm install           Install all dependencies listed in package.json
  npm install express   Add "express" to your project
  npm run test          Run the "test" script defined in package.json
  npm run build         Run the "build" script defined in package.json
```

`npm` is for **managing** packages -- installing, removing, updating them.

When you run `npm run <script>`, it looks in `package.json`:
```json
{
  "scripts": {
    "test": "vitest",
    "build": "next build"
  }
}
```

---

## npx (Node Package Execute)

```
  npx tsx main.ts       Run "tsx" (TypeScript executor) without installing it globally
  npx drizzle-kit push  Run "drizzle-kit" CLI
  npx create-next-app   Scaffold a new Next.js app
```

`npx` is for **running** a package's command. It:

1. Checks if the command exists locally (in `node_modules/.bin/`)
2. If yes, runs it
3. If no, temporarily downloads it, runs it, then discards it

---

## Visual Comparison

```
  npm install             npx tsx main.ts
  ===========             ================

  "Go to the store        "Just run this tool.
   and buy a hammer.       I don't care if you already
   Put it in the           own it or need to borrow it.
   toolbox."               Just get the job done."

  Result: hammer is       Result: main.ts is executed.
  now in node_modules/    tsx may or may not stick around.
```

---

## In the AFK Codebase

### `ralph/afk.sh`:
```bash
# npx is NOT used -- Ralph runs claude directly inside Docker
claude --print "$RALPH_PROMPT"
```

### `sandcastle/afk.sh`:
```bash
npx tsx .sandcastle/main.ts "$inputs" "$MAX_ITER"
```

```
  npx tsx .sandcastle/main.ts
  --- --- -------------------
   |   |         |
   |   |         +-- The TypeScript file to run
   |   +-- tsx = a tool that runs .ts files directly (no compile step)
   +-- "find tsx in node_modules and run it"
```

Without `npx`, you'd need to either:
- Install tsx globally: `npm install -g tsx` then `tsx main.ts`
- Use the full path: `./node_modules/.bin/tsx main.ts`

`npx` is just a shortcut.

---

## tsx (TypeScript Execute)

`tsx` is a tool that **runs TypeScript files directly** without a separate
compile step.

Normally TypeScript requires two steps:

```
  tsc main.ts    -->  main.js     (compile TS to JS)
  node main.js                    (run the JS)
```

`tsx` combines them:

```
  tsx main.ts                     (compile + run in one shot)
```

In the AFK codebase, it's used in `sandcastle/afk.sh`:

```bash
npx tsx .sandcastle/main.ts "$inputs" "$MAX_ITER"
```

That's saying: "run this TypeScript file right now, don't make me compile it
first."

The name `tsx` stands for **TypeScript Execute** (not to be confused with
`.tsx` files, which are TypeScript + React JSX).

### Does tsx produce a persistent main.js?

No. `tsx` compiles in memory -- no `main.js` file is ever written to disk.
It compiles, runs, and throws away the compiled version all in one process.

```
  tsc + node (two steps):
  =======================
  main.ts  --tsc-->  main.js (written to disk)  --node-->  runs
                     ^^^^^^^^
                     this file persists

  tsx (one shot):
  ===============
  main.ts  --[compile in RAM]--> runs

           nothing written to disk
```

---

## Why pnpm Instead of npm?

You'll see `pnpm` in this codebase too. It's an alternative to `npm`.
Three major alternatives exist:

```
  npm    = the default, comes with Node.js
  pnpm   = faster, uses less disk space (shares packages across projects)
  yarn   = another alternative (by Facebook/Meta)
```

### The Problem with npm: Duplicate Copies Everywhere

npm installs a **separate copy** of every package into each project:

```
  project-A/node_modules/
    lodash@4.17.21/       <-- 1.4 MB
    react@19.1.0/         <-- 900 KB

  project-B/node_modules/
    lodash@4.17.21/       <-- 1.4 MB  (identical copy!)
    react@19.1.0/         <-- 900 KB  (identical copy!)

  project-C/node_modules/
    lodash@4.17.21/       <-- 1.4 MB  (identical copy!)

  Total: 3 copies of lodash = 4.2 MB wasted
```

With dozens of projects and hundreds of packages, this adds up to **gigabytes**
of duplicate files.

### How pnpm Fixes This: A Global Store + Links

pnpm keeps ONE copy of each package version in a global store, then creates
**hard links** (pointers) from each project:

```
  ~/.pnpm-store/                     <-- global store (ONE copy of each package)
    lodash@4.17.21/       1.4 MB
    react@19.1.0/         900 KB

  project-A/node_modules/
    lodash --> link to store          <-- ~0 bytes (just a pointer)
    react  --> link to store          <-- ~0 bytes

  project-B/node_modules/
    lodash --> link to store          <-- ~0 bytes
    react  --> link to store          <-- ~0 bytes

  Total disk used: 1 copy of each = 2.3 MB (not 6.9 MB)
```

### Speed

Because pnpm doesn't need to copy files, installs are faster:

```
  npm install     -->  download + copy into node_modules    (slow)
  pnpm install    -->  download once + create links         (fast)
                       (skip download if already in store)
```

### Strictness

pnpm is also **stricter** than npm. With npm, you can accidentally use a
package you didn't declare in `package.json` (because a dependency's
dependency installed it). pnpm prevents this:

```
  npm (loose):
  ============
  You declared: express
  Express depends on: accepts
  Your code: import accepts   <-- WORKS (but shouldn't -- you didn't declare it)

  pnpm (strict):
  ==============
  You declared: express
  Express depends on: accepts
  Your code: import accepts   <-- ERROR: not in your package.json
```

This catches hidden dependencies before they cause problems in production.

### Why This Project Uses pnpm

The course (AI Hero cohort) standardized on pnpm. The `pnpm-lock.yaml` lockfile
is committed to the repo. Everyone uses the same tool so dependencies resolve
identically across machines.

If you tried to use `npm install` on this project, it would:
1. Ignore `pnpm-lock.yaml` (npm doesn't read it)
2. Create its own `package-lock.json`
3. Potentially install different versions
4. Break reproducibility

### Does pnpm Use npm Under the Hood?

No. pnpm is a completely separate tool with its own codebase. It talks directly
to the same **npm registry** (the package server at registry.npmjs.org) to
download packages, but the installer, resolver, and storage mechanism are all
its own.

```
  npm    --> registry.npmjs.org --> copy into node_modules/
  pnpm   --> registry.npmjs.org --> store globally, link into node_modules/
  yarn   --> registry.npmjs.org --> its own approach too

             ^^^^^^^^^^^^^^^^^^
             Same "warehouse" of packages.
             Different delivery trucks.
```

They share the registry (the source of packages), not any code.

### Command Comparison

```
  npm install        -->  pnpm install
  npm run test       -->  pnpm run test
  npm run build      -->  pnpm run build
  npx tsx main.ts    -->  pnpm exec tsx main.ts  (or just: pnpm tsx main.ts)
```

The commands are nearly identical -- just swap `npm` for `pnpm`.
