import { run, claudeCode } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";

const [, , planAndPrd, maxIterations] = process.argv;

await run({
  sandbox: docker(),
  agent: claudeCode("claude-sonnet-4-6"),
  promptFile: `.sandcastle/sandcastle-prompt.md`,
  maxIterations: Number(maxIterations) ?? 3,
  promptArgs: {
    INPUTS: planAndPrd,
  },
  hooks: {
    // "pnpm rebuild" instead of "pnpm install" — recompiles native modules
    // (rollup, better-sqlite3) for Linux without replacing the entire
    // bind-mounted node_modules, which would overwrite macOS binaries.
    onSandboxReady: [{ command: "pnpm rebuild" }],
  },
  completionSignal: "<promise>NO MORE TASKS</promise>",
});
