import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const result = spawnSync(
  "corepack",
  [
    "pnpm",
    "exec",
    "vp",
    "test",
    "--run",
    "src/features/definitions/definitions.test.ts",
    "-t",
    "producer supplied",
  ],
  {
    cwd: fileURLToPath(new URL("../../../", import.meta.url)),
    env: { ...process.env, CADENCE_DERIVED_PAGE: process.argv[2] },
    encoding: "utf8",
    timeout: 60000,
    maxBuffer: 1024 * 1024,
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
process.exit(result.status ?? 1);
