// The 400-line rule (CLAUDE.md "No file over 400 lines"; lead 11-16): frontend source files stay at
// or under MAX_LINES. Today's longer files are listed in file-lines-baseline.json, each capped at its
// current length, so they can only shrink until their owners split them.
import { readdir, readFile } from "node:fs/promises";
import { join, relative, sep } from "node:path";

export const MAX_LINES = 400;
/** Source roots, relative to frontend/. */
const ROOTS = ["apps", "packages", "modules"];
const SOURCE = /\.(?:ts|vue|js|mjs)$/;
/** Tests, test support, declarations, generated files and vendored code don't count. */
const SKIPPED = [
  /\.test\.(?:ts|mjs)$/,
  /\.test-support\.ts$/,
  /\.d\.ts$/,
  /\.generated\.ts$/,
  /(?:^|\/)vendor\//,
  /(?:^|\/)node_modules\//,
];

/** Lines as `wc -l` counts them (newline characters). */
export const lineCount = (/** @type {string} */ text) => text.split("\n").length - 1;

/**
 * Every counted source file under each `<root>/<package>/src`, as frontend-relative paths with
 * forward slashes, and its line count.
 * @param {string} frontend
 * @returns {Promise<Record<string, number>>}
 */
export async function sourceLineCounts(frontend) {
  /** @type {Record<string, number>} */
  const counts = {};
  /** @param {string} dir */
  async function walk(dir) {
    for (const entry of await readdir(dir, { withFileTypes: true })) {
      const path = join(dir, entry.name);
      const rel = relative(frontend, path).split(sep).join("/");
      if (SKIPPED.some((re) => re.test(rel))) continue;
      if (entry.isDirectory()) await walk(path);
      else if (entry.isFile() && SOURCE.test(entry.name))
        counts[rel] = lineCount(await readFile(path, "utf8"));
    }
  }
  for (const root of ROOTS) {
    for (const pkg of await readdir(join(frontend, root), { withFileTypes: true })) {
      if (!pkg.isDirectory()) continue;
      const src = join(frontend, root, pkg.name, "src");
      try {
        await walk(src);
      } catch (error) {
        if (!(error instanceof Error && "code" in error && error.code === "ENOENT")) throw error;
      }
    }
  }
  return counts;
}

/**
 * What's wrong, one sentence per file: a new long file, a baselined one that grew, shrank below
 * its cap (lower the cap), is back under the limit (remove it), or is gone (remove it).
 * @param {Readonly<Record<string, number>>} counts
 * @param {Readonly<Record<string, number>>} baseline
 * @returns {string[]}
 */
export function fileLineProblems(counts, baseline) {
  /** @type {string[]} */
  const problems = [];
  for (const [file, lines] of Object.entries(counts)) {
    if (lines <= MAX_LINES || file in baseline) continue;
    problems.push(`${file}: ${lines} lines, over ${MAX_LINES}; split it by concern`);
  }
  for (const [file, cap] of Object.entries(baseline)) {
    const lines = counts[file];
    if (lines === undefined)
      problems.push(`${file}: no longer exists; remove it from file-lines-baseline.json`);
    else if (lines <= MAX_LINES)
      problems.push(
        `${file}: ${lines} lines, within ${MAX_LINES}; remove it from file-lines-baseline.json`,
      );
    else if (lines > cap)
      problems.push(`${file}: grew to ${lines} lines (cap ${cap}); split it instead`);
    else if (lines < cap)
      problems.push(`${file}: shrank to ${lines} lines; lower its cap in file-lines-baseline.json`);
  }
  return problems.sort();
}
