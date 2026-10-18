import { spawnSync } from "node:child_process";
import { access, readdir, readFile } from "node:fs/promises";
import { createRequire } from "node:module";
import { join, relative, resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import ts from "typescript";

const containers = ["apps", "modules", "packages"];
const excluded = new Set([
  "node_modules",
  "dist",
  "coverage",
  "storybook-static",
  ".git",
  "vendor",
]);
const authoredSource = /\.(?:[cm]?[jt]sx?|vue)$/;
const javascriptSource = /\.[cm]?jsx?$/;
const compiler = createRequire(import.meta.url).resolve("vue-tsc/bin/vue-tsc.js");
const strictOptions = ["strict", "noUncheckedIndexedAccess", "exactOptionalPropertyTypes"];

/** @param {string} path */
async function exists(path) {
  try {
    await access(path);
    return true;
  } catch (error) {
    if (error instanceof Error && "code" in error && error.code === "ENOENT") return false;
    throw error;
  }
}

/** @param {string} directory @returns {Promise<string[]>} */
async function sourceFiles(directory) {
  const files = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (excluded.has(item.name)) continue;
    const path = join(directory, item.name);
    if (item.isFile() && authoredSource.test(item.name)) files.push(path);
    if (item.isDirectory()) files.push(...(await sourceFiles(path)));
  }
  return files;
}

/** @param {unknown} value @returns {value is Record<string, unknown>} */
const record = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
/** @param {string} root */
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
      else if ((await sourceFiles(project)).length)
        throw new Error(
          `${relative(root, project)} has authored TypeScript, JavaScript or Vue sources but no tsconfig.json`,
        );
    }
  }
  if (!(await exists(join(root, "tsconfig.tools.json"))))
    throw new Error("Missing root tools type-check configuration");
  projects.push("tsconfig.tools.json");
  projects.sort();
  const config = /** @type {unknown} */ (
    JSON.parse(await readFile(join(root, "tsconfig.json"), "utf8"))
  );
  if (!record(config) || !Array.isArray(config.references))
    throw Error(
      "Root tsconfig references must include every workspace type-check project exactly once",
    );
  const references = config.references
    .map((reference) => {
      if (!record(reference) || typeof reference.path !== "string")
        throw Error("Invalid root tsconfig reference");
      return relative(root, resolve(root, reference.path));
    })
    .sort();
  if (JSON.stringify(references) !== JSON.stringify(projects))
    throw new Error(
      "Root tsconfig references must include every workspace type-check project exactly once",
    );
  return projects;
}

/** Inspect only referenced compiler projects. An unused config cannot hide an unchecked file.
 * @param {string} root @param {string[]} projects */
export async function assertWorkspaceCoverage(root, projects) {
  const authored = (await sourceFiles(root)).filter(
    (file) => !relative(root, file).startsWith("ast-grep/fixtures/"),
  );
  const covered = new Set();
  const checkedJs = new Set();
  const visited = new Set();
  /** @param {string} candidate */
  function inspect(candidate) {
    const configPath = candidate.endsWith(".json") ? candidate : join(candidate, "tsconfig.json");
    if (visited.has(configPath)) return;
    visited.add(configPath);
    const source = ts.readJsonConfigFile(configPath, (path) => ts.sys.readFile(path));
    const config = ts.parseJsonSourceFileConfigFileContent(
      source,
      ts.sys,
      dirname(configPath),
      undefined,
      configPath,
      undefined,
      [{ extension: "vue", isMixedContent: true, scriptKind: ts.ScriptKind.Deferred }],
    );
    if (config.errors.length)
      throw Error(
        ts.formatDiagnosticsWithColorAndContext(config.errors, {
          getCurrentDirectory: () => root,
          getCanonicalFileName: (path) => path,
          getNewLine: () => "\n",
        }),
      );
    if (config.fileNames.length) {
      if (config.options.noCheck === true)
        throw Error(`${relative(root, configPath)} cannot enable noCheck`);
      for (const option of strictOptions)
        if (config.options[option] !== true)
          throw Error(`${relative(root, configPath)} must enable ${option}`);
    }
    for (const file of config.fileNames) {
      covered.add(file);
      if (config.options.checkJs === true) checkedJs.add(file);
    }
    for (const reference of config.projectReferences ?? []) inspect(reference.path);
  }
  for (const project of projects) inspect(resolve(root, project));
  const missing = authored.filter(
    (file) => !covered.has(file) || (javascriptSource.test(file) && !checkedJs.has(file)),
  );
  if (missing.length)
    throw Error(
      `Authored frontend files must belong to a checked compiler project (JavaScript requires checkJs):\n${missing
        .map((file) => relative(root, file))
        .sort()
        .join("\n")}`,
    );
}

/** @param {string} root */
export async function checkWorkspace(root) {
  const projects = await discoverTypecheckProjects(root);
  await assertWorkspaceCoverage(root, projects);
  const result = spawnSync(process.execPath, [compiler, "--build", ...projects], {
    cwd: root,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (result.error) throw result.error;
  return { ...result, projects };
}
const entry = process.argv[1];
if (entry && import.meta.url === pathToFileURL(resolve(entry)).href) {
  try {
    const result = await checkWorkspace(resolve(fileURLToPath(new URL("..", import.meta.url))));
    process.stdout.write(result.stdout);
    process.stderr.write(result.stderr);
    if (result.status === 0)
      console.log(
        `Vue-aware type checking passed for ${result.projects.length} workspace projects, including all authored sources, tests and tools.`,
      );
    process.exitCode = result.status ?? 1;
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
  }
}
