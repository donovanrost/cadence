import { lstatSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";

/** @param {string} message @returns {never} */
function fail(message) {
  throw new Error(`Frontend release output check failed: ${message}`);
}

/** @param {string[]} argumentsList @returns {string} */

export function parseOutputDirectoryArgument(argumentsList) {
  const values = [];

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    if (argument === undefined) fail("argument list is sparse");
    let value;

    if (argument === "--outDir") {
      value = argumentsList[index + 1];
      index += 1;
      if (!value || value.startsWith("-")) {
        fail("--outDir requires one absolute, non-option value");
      }
    } else if (argument.startsWith("--outDir=")) {
      value = argument.slice("--outDir=".length);
      if (!value || value.startsWith("-")) {
        fail("--outDir requires one absolute, non-option value");
      }
    } else if (argument.startsWith("--outDir")) {
      fail("--outDir option is malformed");
    } else {
      continue;
    }

    if (!isAbsolute(value)) {
      fail("--outDir requires one absolute, non-option value");
    }
    values.push(value);
  }

  if (values.length !== 1) {
    fail("exactly one --outDir with one absolute, non-option value is required");
  }

  return values[0] ?? fail("required argument is missing");
}

/** @param {string} path */

export function canonicalPathWithMissingTail(path) {
  const missingTail = [];
  let current = resolve(path);

  while (true) {
    try {
      const canonicalExisting = realpathSync(current);
      if (!statSync(canonicalExisting).isDirectory())
        fail("output must be a directory with directory parents");
      return resolve(canonicalExisting, ...missingTail.reverse());
    } catch {
      let existingEntry;
      try {
        existingEntry = lstatSync(current);
      } catch (lstatError) {
        if (!(lstatError instanceof Error && "code" in lstatError && lstatError.code === "ENOENT"))
          throw lstatError;
      }

      if (existingEntry) {
        fail(`cannot resolve output path component ${JSON.stringify(current)}`);
      }

      const parent = dirname(current);
      if (parent === current) fail("output path cannot be resolved");
      missingTail.push(basename(current));
      current = parent;
    }
  }
}

/** @param {string} left @param {string} right */

export function pathsOverlap(left, right) {
  /** @param {string} parent @param {string} child */
  const contains = (parent, child) => {
    const childRelative = relative(parent, child);
    return (
      childRelative === "" ||
      (childRelative !== ".." &&
        !childRelative.startsWith(`..${sep}`) &&
        !isAbsolute(childRelative))
    );
  };

  return contains(left, right) || contains(right, left);
}

/** @param {string} outputRoot @param {string} canonicalRepositoryRoot */

export function assertOutputOutsideRepository(outputRoot, canonicalRepositoryRoot) {
  if (pathsOverlap(canonicalRepositoryRoot, outputRoot)) {
    fail("output directory must be outside the repository in both directions");
  }
}
