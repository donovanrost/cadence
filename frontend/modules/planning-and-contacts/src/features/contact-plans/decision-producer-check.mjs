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
      "src/features/contact-plans/contact-plans.test.ts",
      "-t",
      "producer-supplied plan review",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: {
        ...process.env,
        NO_COLOR: "1",
        CADENCE_PLAN_REVIEW_MODEL: process.argv[2],
        CADENCE_PLAN_REVIEW_ACTION: process.argv[3],
      },
      timeout: 60000,
      maxBuffer: 1048576,
      encoding: "utf8",
    },
  ),
);
