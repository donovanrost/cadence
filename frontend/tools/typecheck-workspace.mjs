import { spawnSync } from "node:child_process";
import { access, readdir, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const containers = ["apps", "modules", "packages"];
const excluded = new Set(["node_modules", "dist", "coverage", "storybook-static", ".git"]);
const typedSource = /\.(?:[cm]?tsx?|vue)$/;
const compiler = createRequire(import.meta.url).resolve("vue-tsc/bin/vue-tsc.js");

async function exists(path) {
  try {
    await access(path);
    return true;
  } catch (error) {
    if (error.code === "ENOENT") return false;
    throw error;
  }
}

async function hasTypedSource(directory) {
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (excluded.has(item.name)) continue;
    if (item.isFile() && typedSource.test(item.name)) return true;
    if (item.isDirectory() && (await hasTypedSource(join(directory, item.name)))) return true;
  }
  return false;
}

export async function discoverTypecheckProjects(root) {
  const projects = [];
  for (const container of containers) {
    const directory = join(root, container);
    if (!(await exists(directory))) continue;
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue;
      const project = join(directory, entry.name);
      if (!(await exists(join(project, "package.json")))) continue;
      if (await exists(join(project, "tsconfig.json"))) projects.push(relative(root, project));
      else if (await hasTypedSource(project))
        throw new Error(
          `${relative(root, project)} has TypeScript or Vue sources but no tsconfig.json`,
        );
    }
  }
  if (!(await exists(join(root, "tsconfig.tools.json"))))
    throw new Error("Missing root tools type-check configuration");
  projects.push("tsconfig.tools.json");
  projects.sort();
  const config = JSON.parse(await readFile(join(root, "tsconfig.json"), "utf8"));
  const references = (config.references ?? [])
    .map(({ path }) => relative(root, resolve(root, path)))
    .sort();
  if (JSON.stringify(references) !== JSON.stringify(projects))
    throw new Error(
      "Root tsconfig references must include every workspace type-check project exactly once",
    );
  return projects;
}

export async function checkWorkspace(root) {
  const projects = await discoverTypecheckProjects(root);
  const result = spawnSync(process.execPath, [compiler, "--build", ...projects], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  return { ...result, projects };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const result = await checkWorkspace(resolve(fileURLToPath(new URL("..", import.meta.url))));
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    if (result.status === 0)
      console.log(
        `Vue-aware type checking passed for ${result.projects.length} workspace projects.`,
      );
    process.exitCode = result.status ?? 1;
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
