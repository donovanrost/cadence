import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../", import.meta.url));
const result = spawnSync(
  "corepack",
  [
    "pnpm",
    "exec",
    "vp",
    "test",
    "--run",
    "src/features/packet-bindings/packet-bindings.test.ts",
    "-t",
    "producer supplied",
  ],
  {
    cwd: root,
    env: { ...process.env, CADENCE_PACKET_PAGE: process.argv[2] },
    encoding: "utf8",
    timeout: 60000,
    maxBuffer: 1024 * 1024,
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
process.exit(result.status ?? 1);
