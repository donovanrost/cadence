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
      "src/features/fleet-planning/fleet-run.test.ts",
      "-t",
      "producer-supplied fleet run workflow",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: { ...process.env, NO_COLOR: "1", CADENCE_FLEET_RUN: process.argv[2] },
      timeout: 60000,
      maxBuffer: 1048576,
      encoding: "utf8",
    },
  ),
);
