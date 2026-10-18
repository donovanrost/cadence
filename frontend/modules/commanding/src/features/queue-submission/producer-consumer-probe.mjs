import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
const root = fileURLToPath(new URL("../../../", import.meta.url));
const temporary = mkdtempSync(join(tmpdir(), "cadence-queue-submission-")),
  inputFile = join(temporary, "input.json");
try {
  const result = spawnSync(
    process.execPath,
    [
      root + "node_modules/vite-plus/bin/vp",
      "test",
      "src/features/queue-submission/QueueSubmission.test.ts",
      "-t",
      "actual producer",
    ],
    {
      cwd: root,
      encoding: "utf8",
      env: {
        ...process.env,
        CADENCE_COMMAND_QUEUE_DOCUMENT: process.argv[2],
        CADENCE_COMMAND_QUEUE_INPUT_FILE: inputFile,
      },
    },
  );
  process.stdout.write(result.stdout ?? "");
  process.stderr.write(result.stderr ?? "");
  if (result.status === 0)
    console.log("COMMAND_QUEUE_INPUT=" + readFileSync(inputFile).toString("base64"));
  process.exitCode = result.status ?? 1;
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
