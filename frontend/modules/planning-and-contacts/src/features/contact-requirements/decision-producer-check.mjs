import { execFileSync } from "node:child_process";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

// Exercise client compilation and native controls with actual producer props.
const input = process.argv[2];
if (input === undefined) throw Error("Missing native review fixture");
/** @type {unknown} */
const props = JSON.parse(input);
process.stdout.write(
  execFileSync(
    "corepack",
    [
      "pnpm",
      "exec",
      "vp",
      "test",
      "--run",
      "src/features/contact-requirements/requirement-detail.test.ts",
      "-t",
      "producer-supplied review",
      "--silent=false",
    ],
    {
      cwd: resolve(dirname(fileURLToPath(import.meta.url)), "../../.."),
      env: {
        ...process.env,
        NO_COLOR: "1",
        CADENCE_REQUIREMENT_REVIEW_MODEL: JSON.stringify(props),
      },
      timeout: 60_000,
      maxBuffer: 1_048_576,
      encoding: "utf8",
    },
  ),
);
