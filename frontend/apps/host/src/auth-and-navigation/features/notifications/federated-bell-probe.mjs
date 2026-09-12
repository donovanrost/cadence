import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../../", import.meta.url));
const result = spawnSync(
  process.execPath,
  [
    root + "node_modules/vite-plus/bin/vp",
    "test",
    "src/auth-and-navigation/features/notifications/federated-notification-bell.test.ts",
    "-t",
    "actual native bell",
  ],
  {
    cwd: root,
    encoding: "utf8",
    env: { ...process.env, CADENCE_FEDERATED_BELL_DOCUMENT: process.argv[2] },
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
if (result.status === 0) console.log("FEDERATED_BELL_CONSUMER_OK");
process.exit(result.status ?? 1);
