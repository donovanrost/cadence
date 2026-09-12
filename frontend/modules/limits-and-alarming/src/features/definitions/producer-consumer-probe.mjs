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
    process.argv[3] === "activity"
      ? "src/features/posture/posture.test.ts"
      : "src/features/definitions/definitions.test.ts",
    "-t",
    "producer supplied",
  ],
  {
    cwd: fileURLToPath(new URL("../../../", import.meta.url)),
    env: {
      ...process.env,
      CADENCE_LIMITS_PAGE: process.argv[3] === "activity" ? undefined : process.argv[2],
      CADENCE_LIMITS_POSTURE: process.argv[3] === "activity" ? process.argv[2] : undefined,
    },
    encoding: "utf8",
    timeout: 60000,
    maxBuffer: 1024 * 1024,
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
process.exit(result.status ?? 1);
