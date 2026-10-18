import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../../", import.meta.url));
const temporary = mkdtempSync(join(tmpdir(), "cadence-platform-probe-"));
const inputFile = join(temporary, "input.json");
const result = spawnSync(
  process.execPath,
  [
    root + "node_modules/vite-plus/bin/vp",
    "test",
    "src/administration/features/organization-detail/organization-detail.test.ts",
    "-t",
    "actual producer",
  ],
  {
    cwd: root,
    encoding: "utf8",
    env: {
      ...process.env,
      CADENCE_PLATFORM_DETAIL_DOCUMENT: process.argv[2],
      CADENCE_PLATFORM_INPUT_FILE: inputFile,
    },
  },
);
process.stdout.write(result.stdout ?? "");
process.stderr.write(result.stderr ?? "");
if (result.status === 0)
  console.log("ADMIN_DETAIL_INPUT=" + readFileSync(inputFile).toString("base64"));
rmSync(temporary, { recursive: true, force: true });
process.exit(result.status ?? 1);
