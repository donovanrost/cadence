import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../", import.meta.url));
const result = spawnSync(
  "node",
  [
    root + "/node_modules/vite-plus/bin/vp",
    "test",
    "src/features/alarm-conditions/alarm-conditions.test.ts",
    "-t",
    "public alarm contribution",
  ],
  { cwd: root, env: { ...process.env, CADENCE_ALARM_DOCUMENT: process.argv[2] }, encoding: "utf8" },
);
process.stdout.write(result.stdout || "");
process.stderr.write(result.stderr || "");
process.exit(result.status ?? 1);
