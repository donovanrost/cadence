import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../", import.meta.url));
const result = spawnSync(
  process.execPath,
  [
    root + "node_modules/vite-plus/bin/vp",
    "test",
    "src/features/spacecraft-commanding/SpacecraftCommanding.test.ts",
    "-t",
    "actual producer",
  ],
  {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, CADENCE_SPACECRAFT_COMMANDING_DOCUMENT: process.argv[2] },
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
if (result.status === 0) console.log("SPACECRAFT_COMMANDING_CONSUMER_OK");
process.exit(result.status ?? 1);
