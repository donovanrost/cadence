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
      "src/features/contact-scheduling/contact-scheduling.test.ts",
      "-t",
      "producer-supplied contact scheduling workflow",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: {
        ...process.env,
        NO_COLOR: "1",
        CADENCE_SCHEDULE_MODEL: process.argv[2],
        CADENCE_SCHEDULE_ACTION: process.argv[3],
        CADENCE_SCHEDULE_RESULT: process.argv[4] ?? "null",
      },
      timeout: 60000,
      maxBuffer: 1048576,
      encoding: "utf8",
    },
  ),
);
