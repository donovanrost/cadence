import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
process.stdout.write(
  execFileSync(
    "corepack",
    [
      "pnpm",
      "exec",
      "vp",
      "test",
      "--run",
      "src/features/fleet-planning/policy-workflow.test.ts",
      "-t",
      "producer-supplied policy contribution sends native payloads and admits completed receipts",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: { ...process.env, NO_COLOR: "1", CADENCE_POLICY_WORKFLOW: process.argv[2] },
      timeout: 60000,
      maxBuffer: 1048576,
      encoding: "utf8",
    },
  ),
);
