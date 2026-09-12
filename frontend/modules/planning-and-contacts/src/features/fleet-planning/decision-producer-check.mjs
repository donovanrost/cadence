import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Use the same client-side Vue compilation and DOM environment as the feature
// tests, with real server-produced props. SSR output cannot exercise DOM events.
const input = process.argv[2];
if (input === undefined) throw Error("Missing native decision fixture");
/** @type {unknown} */
const model = JSON.parse(input);
const output = execFileSync(
  "corepack",
  [
    "pnpm",
    "exec",
    "vp",
    "test",
    "--run",
    "src/features/fleet-planning/policy-decisions.test.ts",
    "-t",
    "producer-supplied decision",
    "--silent=false",
  ],
  {
    cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
    env: { ...process.env, NO_COLOR: "1", CADENCE_FLEET_DECISION_MODEL: JSON.stringify(model) },
    timeout: 60_000,
    maxBuffer: 1_048_576,
    encoding: "utf8",
  },
);
process.stdout.write(output);
