import { readdir, readFile } from "node:fs/promises";
import { relative, resolve } from "node:path";

const publicationRoot = resolve(
  import.meta.dirname,
  "../../apps/cadence_web/priv/static/assets/application-host",
);

const publicationBundles = ["host", "comms-overview", "telemetry-decom"];

async function javascriptFiles(root) {
  const files = [];

  for (const entry of await readdir(root, { withFileTypes: true })) {
    const path = resolve(root, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await javascriptFiles(path)));
    } else if (entry.isFile() && path.endsWith(".js")) {
      files.push(path);
    }
  }

  return files;
}

const violations = [];

for (const bundle of publicationBundles) {
  const root = resolve(publicationRoot, bundle);
  const files = await javascriptFiles(root);

  if (files.length === 0) {
    throw new Error(`Published bundle ${bundle} contains no JavaScript files: ${root}`);
  }

  for (const file of files) {
    const source = await readFile(file, "utf8");

    if (/\bprocess\s*\.\s*env\s*\.\s*NODE_ENV\b/.test(source)) {
      violations.push(relative(publicationRoot, file));
    }
  }
}

if (violations.length > 0) {
  throw new Error(
    `Published JavaScript retains a process.env.NODE_ENV reference:\n${violations
      .map((file) => `- ${file}`)
      .join("\n")}`,
  );
}

console.log(
  `Production publication check passed: ${publicationBundles.join(", ")} contain no process.env.NODE_ENV references.`,
);
