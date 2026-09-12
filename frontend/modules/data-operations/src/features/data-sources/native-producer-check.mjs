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
      "src/features/data-sources/native-workflow.test.ts",
      "-t",
      "producer supplied native source contribution",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: { ...process.env, NO_COLOR: "1", CADENCE_SOURCES: process.argv[2] },
      timeout: 60000,
      maxBuffer: 1048576,
      encoding: "utf8",
    },
  ),
);
