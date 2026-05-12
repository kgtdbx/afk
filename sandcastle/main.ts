import { run, claudeCode, codex } from "@ai-hero/sandcastle";
import { docker } from "@ai-hero/sandcastle/sandboxes/docker";
import { existsSync } from "node:fs";
import { join } from "node:path";

const [, , planAndPrd, maxIterations, agentName] = process.argv;

const agents: Record<string, () => ReturnType<typeof claudeCode>> = {
  claude: () => claudeCode("claude-opus-4-6"),
  codex: () => codex("gpt-5.5"),
};

const selectedAgent = agents[agentName || "claude"]!;

// Only mount ~/.codex when it exists (Codex OAuth credentials)
const mounts: { hostPath: string; sandboxPath: string }[] = [];
const codexDir = join(process.env.HOME ?? "~", ".codex");
if (existsSync(codexDir)) {
  mounts.push({ hostPath: "~/.codex", sandboxPath: "~/.codex" });
}

await run({
  sandbox: docker({ mounts }),
  agent: selectedAgent(),
  promptFile: `.sandcastle/sandcastle-prompt.md`,
  maxIterations: Number(maxIterations) ?? 3,
  promptArgs: {
    INPUTS: planAndPrd,
  },
  hooks: {
    // "pnpm rebuild" instead of "pnpm install" — recompiles native modules
    // (rollup, better-sqlite3) for Linux without replacing the entire
    // bind-mounted node_modules, which would overwrite macOS binaries.
    sandbox: {
      onSandboxReady: [{ command: "pnpm install --store-dir /tmp/pnpm-store" }],
    },
  },
  completionSignal: "<promise>NO MORE TASKS</promise>",
});
