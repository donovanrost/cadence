import { lstatSync, realpathSync, statSync } from "node:fs";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import { basename, dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const remoteNamePattern = /^[a-z][a-z0-9._-]{0,127}$/;
const releaseMetadataFiles = new Set(["mf-manifest.json", "mf-stats.json"]);
const forbiddenArtifactNamePattern =
  /(?:^|[-_.])(?:contract[-_.]?probe|demo[-_.]?auth(?:[-_.]?service)?|failure[-_.]?application|index|main|phoenix[-_.]?main|phoenix[-_.]?bootstrap|standalone|spec|test)(?:[-_.]|$)/i;

function fail(message) {
  throw new Error(`Release output check failed: ${message}`);
}

export function assertReleaseArtifactPath(path) {
  const lowerPath = path.toLowerCase();
  const name = basename(path);

  if (lowerPath.endsWith(".map")) fail(`source-map artifact ${JSON.stringify(path)} is forbidden`);
  if (lowerPath.endsWith(".html")) {
    fail(`standalone HTML artifact ${JSON.stringify(path)} is forbidden`);
  }
  if (!releaseMetadataFiles.has(path) && path !== "remoteEntry.js" && !path.startsWith("assets/")) {
    fail(`unexpected release artifact ${JSON.stringify(path)}`);
  }
  if (forbiddenArtifactNamePattern.test(name)) {
    fail(`standalone, test, or contract artifact ${JSON.stringify(path)} is forbidden`);
  }
}

export function assertNoForbiddenPublicationReferences(source, origin) {
  const forbiddenReferences = [
    ["demo-auth service", /\bdemo[-_]?auth(?:[-_]?service)?\b/i],
    ["contract probe", /(?:\bcontract[-_]?probe\b|cadence[._-]contract[._-]probe)/i],
    [
      "development URL",
      /\bhttps?:\/\/(?:localhost|127(?:\.\d{1,3}){3}|\[::1\])(?::\d+)?(?:[/?#"'`),;\s]|$)/i,
    ],
    [
      "Vite client or HMR reference",
      /(?:import\.meta\.hot|\/[@]vite\/client|vite\/client|hotUpdate|__vite__hot)/i,
    ],
    ["source-map reference", /(?:sourceMappingURL|\.map(?:["'`?#),]|$))/i],
    ["standalone bootstrap reference", /(?:phoenix[-_.]?main|phoenix[-_.]?bootstrap|standalone)/i],
    [
      "mutable fallback URL",
      /\b(?:fallback(?:Url|Href)?|artifactBaseUrl)\b\s*(?:[:=])\s*["'`](?:https?:\/\/|\/)/i,
    ],
    [
      "deployment-specific release reference",
      /(?:\/releases\/|MF_BUILD_VERSION|process\.env\.NODE_ENV)/i,
    ],
  ];

  for (const [label, pattern] of forbiddenReferences) {
    if (pattern.test(source)) fail(`${origin} contains a forbidden ${label}`);
  }
}

export function parseOutputDirectoryArgument(argumentsList) {
  const values = [];

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
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

  return values[0];
}

function assertRemoteName(value, label) {
  if (typeof value !== "string" || !remoteNamePattern.test(value)) {
    fail(`${label} must be a valid Module Federation identifier`);
  }
  return value;
}

export function parseRemoteNameArgument(argumentsList) {
  const values = [];

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    let value;

    if (argument === "--remoteName") {
      value = argumentsList[index + 1];
      index += 1;
      if (!value || value.startsWith("-")) {
        fail("--remoteName requires one valid, non-option value");
      }
    } else if (argument.startsWith("--remoteName=")) {
      value = argument.slice("--remoteName=".length);
      if (!value || value.startsWith("-")) {
        fail("--remoteName requires one valid, non-option value");
      }
    } else if (argument.startsWith("--remoteName")) {
      fail("--remoteName option is malformed");
    } else {
      continue;
    }

    values.push(assertRemoteName(value, "--remoteName"));
  }

  if (values.length !== 1) {
    fail("exactly one --remoteName with one valid, non-option value is required");
  }

  return values[0];
}

export function canonicalPathWithMissingTail(path) {
  const missingTail = [];
  let current = resolve(path);

  while (true) {
    try {
      const canonicalExisting = realpathSync(current);
      if (missingTail.length > 0 && !statSync(canonicalExisting).isDirectory()) {
        fail("a missing output path component has a non-directory parent");
      }
      return resolve(canonicalExisting, ...missingTail.reverse());
    } catch {
      let existingEntry;
      try {
        existingEntry = lstatSync(current);
      } catch (lstatError) {
        if (lstatError?.code !== "ENOENT") throw lstatError;
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

export function pathsOverlap(left, right) {
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

export function assertOutputOutsideRepository(outputRoot, canonicalRepositoryRoot) {
  if (pathsOverlap(canonicalRepositoryRoot, outputRoot)) {
    fail("output directory must be outside the repository in both directions");
  }
}

function relativePath(outputRoot, path) {
  return relative(outputRoot, path).split(sep).join("/");
}

async function outputFiles(directory, outputRoot) {
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = [];

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      paths.push(...(await outputFiles(path, outputRoot)));
    } else if (entry.isFile()) {
      paths.push(path);
    } else {
      fail(`unsupported output entry ${relativePath(outputRoot, path)}`);
    }
  }

  return paths;
}

export function assertLocalReference(reference, origin, files, label, outputRoot) {
  const value = reference.trim();
  if (value === "" || /^\$\{[^}]+\}$/.test(value)) return;

  if (/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(value)) return;
  if (value.startsWith("/")) {
    fail(`${label} contains an absolute local reference ${JSON.stringify(value)}`);
  }

  const pathPart =
    value.startsWith("?") || value.startsWith("#") ? origin : value.split(/[?#]/, 1)[0];
  if (pathPart === "") return;

  const target = resolve(outputRoot, dirname(origin), pathPart);
  const targetRelative = relativePath(outputRoot, target);
  if (targetRelative === "" || targetRelative.startsWith("../") || targetRelative === "..") {
    fail(`${label} escapes the output with ${JSON.stringify(value)}`);
  }
  if (!files.has(targetRelative)) {
    fail(`${label} points to missing ${JSON.stringify(targetRelative)}`);
  }
}

function assertManifestPath(value, files, label, outputRoot) {
  if (typeof value !== "string" || value.trim() === "") fail(`${label} is not a path`);
  assertLocalReference(value, "mf-manifest.json", files, label, outputRoot);
}

function assertAssetLists(value, files, label, outputRoot, referencedFiles) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    fail(`${label} is not an asset map`);
  }

  for (const kind of ["js", "css"]) {
    const assets = value[kind];
    if (!assets || typeof assets !== "object" || Array.isArray(assets)) {
      fail(`${label}.${kind} is not an asset map`);
    }
    for (const phase of ["async", "sync"]) {
      if (!Array.isArray(assets[phase])) fail(`${label}.${kind}.${phase} is not a list`);
      for (const asset of assets[phase]) {
        assertManifestPath(asset, files, `${label}.${kind}.${phase}`, outputRoot);
        referencedFiles?.add(asset);
      }
    }
  }
}

function assertGeneratedManifest(manifest, expectedRemoteName, files, outputRoot) {
  if (manifest.id !== expectedRemoteName || manifest.name !== expectedRemoteName) {
    fail(`the federation manifest identity is not ${JSON.stringify(expectedRemoteName)}`);
  }

  const metadata = manifest.metaData;
  if (!metadata || typeof metadata !== "object") fail("manifest metadata is missing");
  if (metadata.publicPath !== "auto")
    fail(`manifest publicPath is ${JSON.stringify(metadata.publicPath)}`);

  const remoteEntry = metadata.remoteEntry;
  if (!remoteEntry || remoteEntry.path !== "" || remoteEntry.name !== "remoteEntry.js") {
    fail("manifest remoteEntry is not the relocatable remoteEntry.js");
  }
  assertManifestPath(remoteEntry.name, files, "manifest remoteEntry.name", outputRoot);
  const referencedFiles = new Set([remoteEntry.name]);

  if (!Array.isArray(manifest.shared) || manifest.shared.length === 0) {
    fail("manifest shared assets are missing");
  }
  for (const shared of manifest.shared) {
    assertAssetLists(
      shared.assets,
      files,
      `manifest shared ${shared.name}`,
      outputRoot,
      referencedFiles,
    );
  }

  if (!Array.isArray(manifest.exposes) || manifest.exposes.length === 0) {
    fail("manifest exposes are missing");
  }
  for (const expose of manifest.exposes) {
    const exposedModule = expose.path ?? expose.name;
    if (
      typeof exposedModule !== "string" ||
      /(?:contract[-_.]?probe|demo[-_.]?auth|failure|spec|test)/i.test(exposedModule)
    ) {
      fail(`manifest exposes a non-publication module ${JSON.stringify(exposedModule)}`);
    }
    assertAssetLists(
      expose.assets,
      files,
      `manifest expose ${expose.name}`,
      outputRoot,
      referencedFiles,
    );
  }

  return referencedFiles;
}

function assertStats(stats, files, outputRoot) {
  if (!Array.isArray(stats.buildOutput) || stats.buildOutput.length === 0) {
    fail("federation buildOutput is missing");
  }
  const referencedFiles = new Set();
  for (const output of stats.buildOutput) {
    assertManifestPath(output.fileName, files, "federation buildOutput.fileName", outputRoot);
    referencedFiles.add(output.fileName);
  }
  return referencedFiles;
}

export function assertViteManifest(manifest, files, outputRoot) {
  if (!manifest || typeof manifest !== "object" || Array.isArray(manifest)) {
    fail(".vite/manifest.json is not a manifest map");
  }

  const manifestKeys = new Set(Object.keys(manifest));
  const visited = new Set();

  function visitManifestEntry(key, trail) {
    if (visited.has(key)) return;
    const entry = manifest[key];
    if (!entry || typeof entry !== "object" || Array.isArray(entry)) {
      fail(`${trail} is not a manifest entry`);
    }

    visited.add(key);
    assertManifestPath(entry.file, files, `${trail}.file`, outputRoot);

    for (const field of ["css", "assets"]) {
      if (entry[field] === undefined) continue;
      if (!Array.isArray(entry[field])) fail(`${trail}.${field} is not a list`);
      for (const asset of entry[field]) {
        assertManifestPath(asset, files, `${trail}.${field}`, outputRoot);
      }
    }

    for (const field of ["imports", "dynamicImports"]) {
      if (entry[field] === undefined) continue;
      if (!Array.isArray(entry[field])) fail(`${trail}.${field} is not a list`);
      for (const importedKey of entry[field]) {
        if (typeof importedKey !== "string" || !manifestKeys.has(importedKey)) {
          fail(`${trail}.${field} references missing manifest key ${JSON.stringify(importedKey)}`);
        }
        visitManifestEntry(importedKey, `${trail}.${field}.${importedKey}`);
      }
    }
  }

  for (const key of manifestKeys) visitManifestEntry(key, `.vite/manifest.${key}`);
}

function javascriptTokens(source) {
  const tokens = [];
  let index = 0;

  while (index < source.length) {
    const character = source[index];
    if (/\s/.test(character)) {
      index += 1;
      continue;
    }
    if (character === "/" && source[index + 1] === "/") {
      index += 2;
      while (index < source.length && source[index] !== "\n") index += 1;
      continue;
    }
    if (character === "/" && source[index + 1] === "*") {
      const end = source.indexOf("*/", index + 2);
      index = end === -1 ? source.length : end + 2;
      continue;
    }
    if (character === "'" || character === '"' || character === "`") {
      const quote = character;
      const template = quote === "`";
      let value = "";
      let dynamic = false;
      index += 1;
      while (index < source.length) {
        const current = source[index];
        if (current === "\\") {
          value += source[index + 1] ?? "";
          index += 2;
          continue;
        }
        if (template && current === "$" && source[index + 1] === "{") dynamic = true;
        if (current === quote) {
          index += 1;
          break;
        }
        value += current;
        index += 1;
      }
      tokens.push({ kind: template ? "template" : "string", value, dynamic });
      continue;
    }
    if (/[A-Za-z_$]/.test(character)) {
      const start = index;
      index += 1;
      while (index < source.length && /[A-Za-z0-9_$]/.test(source[index])) index += 1;
      tokens.push({ kind: "word", value: source.slice(start, index) });
      continue;
    }
    tokens.push({ kind: "punctuation", value: character });
    index += 1;
  }

  return tokens;
}

function staticReferenceToken(token) {
  return token?.kind === "string" || (token?.kind === "template" && token.dynamic === false);
}

function isMemberProperty(tokens, index) {
  return tokens[index - 1]?.value === ".";
}

export function assertImportReferences(source, origin, files, outputRoot) {
  const tokens = javascriptTokens(source);
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    const next = tokens[index + 1];

    if (
      token.kind === "word" &&
      token.value === "from" &&
      !isMemberProperty(tokens, index) &&
      staticReferenceToken(next)
    ) {
      assertLocalReference(next.value, origin, files, `${origin} import`, outputRoot);
      continue;
    }

    if (token.kind === "word" && token.value === "import" && !isMemberProperty(tokens, index)) {
      if (staticReferenceToken(next)) {
        assertLocalReference(next.value, origin, files, `${origin} import`, outputRoot);
        continue;
      }
      if (
        next?.value === "(" &&
        staticReferenceToken(tokens[index + 2]) &&
        tokens[index + 3]?.value === ")"
      ) {
        assertLocalReference(
          tokens[index + 2].value,
          origin,
          files,
          `${origin} import`,
          outputRoot,
        );
      }
      continue;
    }

    if (
      token.kind === "word" &&
      token.value === "new" &&
      tokens[index + 1]?.value === "URL" &&
      tokens[index + 2]?.value === "(" &&
      staticReferenceToken(tokens[index + 3]) &&
      tokens[index + 4]?.value === "," &&
      tokens[index + 5]?.value === "import" &&
      tokens[index + 6]?.value === "." &&
      tokens[index + 7]?.value === "meta" &&
      tokens[index + 8]?.value === "." &&
      tokens[index + 9]?.value === "url" &&
      tokens[index + 10]?.value === ")"
    ) {
      assertLocalReference(
        tokens[index + 3].value,
        origin,
        files,
        `${origin} asset URL`,
        outputRoot,
      );
    }
  }
}

function skipCssTrivia(source, start) {
  let index = start;
  while (index < source.length) {
    if (/\s/.test(source[index])) {
      index += 1;
      continue;
    }
    if (source[index] === "/" && source[index + 1] === "*") {
      const end = source.indexOf("*/", index + 2);
      return end === -1 ? source.length : skipCssTrivia(source, end + 2);
    }
    break;
  }
  return index;
}

function readCssString(source, start) {
  const quote = source[start];
  let index = start + 1;
  let value = "";
  while (index < source.length) {
    if (source[index] === "\\") {
      value += source[index + 1] ?? "";
      index += 2;
      continue;
    }
    if (source[index] === quote) return { value, next: index + 1 };
    value += source[index];
    index += 1;
  }
  return { value, next: source.length };
}

function cssIdentifierAt(source, start) {
  if (!/[A-Za-z_-]/.test(source[start] ?? "")) return null;
  let index = start + 1;
  while (index < source.length && /[A-Za-z0-9_-]/.test(source[index])) index += 1;
  return { value: source.slice(start, index), next: index };
}

function readCssUrlFunction(source, start) {
  const identifier = cssIdentifierAt(source, start);
  if (!identifier || identifier.value.toLowerCase() !== "url") return null;
  let index = skipCssTrivia(source, identifier.next);
  if (source[index] !== "(") return null;
  index = skipCssTrivia(source, index + 1);

  let value;
  if (source[index] === "'" || source[index] === '"') {
    const stringValue = readCssString(source, index);
    value = stringValue.value;
    index = skipCssTrivia(source, stringValue.next);
  } else {
    const startValue = index;
    while (index < source.length && source[index] !== ")") index += 1;
    value = source.slice(startValue, index).trim();
  }

  if (source[index] !== ")") return null;
  return { value, next: index + 1 };
}

export function assertCssReferences(source, origin, files, outputRoot) {
  let index = 0;
  while (index < source.length) {
    if (source[index] === "/" && source[index + 1] === "*") {
      const end = source.indexOf("*/", index + 2);
      index = end === -1 ? source.length : end + 2;
      continue;
    }
    if (source[index] === "'" || source[index] === '"') {
      index = readCssString(source, index).next;
      continue;
    }

    if (source[index] === "@") {
      const atRule = cssIdentifierAt(source, index + 1);
      if (atRule?.value.toLowerCase() === "import") {
        const next = skipCssTrivia(source, atRule.next);
        const url = readCssUrlFunction(source, next);
        if (url) {
          assertLocalReference(url.value, origin, files, `${origin} CSS import`, outputRoot);
          index = url.next;
          continue;
        }
        if (source[next] === "'" || source[next] === '"') {
          const imported = readCssString(source, next);
          assertLocalReference(imported.value, origin, files, `${origin} CSS import`, outputRoot);
          index = imported.next;
          continue;
        }
      }
    }

    const url = readCssUrlFunction(source, index);
    if (url) {
      assertLocalReference(url.value, origin, files, `${origin} CSS URL`, outputRoot);
      index = url.next;
      continue;
    }

    index += 1;
  }
}

function findHtmlTagEnd(source, start) {
  let quote = null;
  for (let index = start + 1; index < source.length; index += 1) {
    const character = source[index];
    if (quote) {
      if (character === quote) quote = null;
    } else if (character === "'" || character === '"') {
      quote = character;
    } else if (character === ">") {
      return index;
    }
  }
  return source.length - 1;
}

function parseHtmlTag(source, start, end) {
  let index = start + 1;
  if (source[index] === "/" || source[index] === "!" || source[index] === "?") {
    return { next: end + 1, tagName: null, closing: true };
  }

  const tag = source.slice(index).match(/^[A-Za-z][A-Za-z0-9:-]*/);
  if (!tag) return { next: end + 1, tagName: null, closing: false };
  const tagName = tag[0].toLowerCase();
  index += tag[0].length;

  while (index <= end) {
    while (index <= end && /\s/.test(source[index])) index += 1;
    if (index > end || source[index] === ">" || source[index] === "/") break;

    const attribute = source.slice(index).match(/^[^\s=/>]+/);
    if (!attribute) {
      index += 1;
      continue;
    }
    const attributeName = attribute[0].toLowerCase();
    index += attribute[0].length;
    while (index <= end && /\s/.test(source[index])) index += 1;

    if (source[index] !== "=") continue;
    index += 1;
    while (index <= end && /\s/.test(source[index])) index += 1;

    let value = "";
    if (source[index] === "'" || source[index] === '"') {
      const quote = source[index];
      index += 1;
      const valueStart = index;
      while (index <= end && source[index] !== quote) index += 1;
      value = source.slice(valueStart, index);
      if (index <= end) index += 1;
    } else {
      const valueStart = index;
      while (index <= end && !/[\s>]/.test(source[index])) index += 1;
      value = source.slice(valueStart, index);
    }

    if (attributeName === "src" || attributeName === "href") {
      return { next: end + 1, tagName, closing: false, reference: value };
    }
  }

  return { next: end + 1, tagName, closing: false };
}

export function assertHtmlReferences(source, origin, files, outputRoot) {
  const lowerSource = source.toLowerCase();
  let index = 0;

  while (index < source.length) {
    if (source.startsWith("<!--", index)) {
      const end = source.indexOf("-->", index + 4);
      index = end === -1 ? source.length : end + 3;
      continue;
    }
    if (source[index] !== "<") {
      index += 1;
      continue;
    }

    const end = findHtmlTagEnd(source, index);
    const tag = parseHtmlTag(source, index, end);
    if (tag.reference !== undefined) {
      assertLocalReference(tag.reference, origin, files, `${origin} HTML reference`, outputRoot);
    }
    index = tag.next;

    if (
      !tag.closing &&
      tag.tagName &&
      ["script", "style", "textarea", "title"].includes(tag.tagName)
    ) {
      const close = lowerSource.indexOf(`</${tag.tagName}`, index);
      if (close === -1) break;
      index = close;
    }
  }
}

async function assertOutputDirectory(outputArgument) {
  const stats = await lstat(outputArgument).catch(() => fail("output directory is unavailable"));
  if (stats.isSymbolicLink()) fail("output directory must not be a symlink");
  if (!stats.isDirectory()) fail("output path must be a directory");
}

function assertDeploymentReferences(source, origin, allowedDeploymentPath) {
  const references = [...source.matchAll(/\/assets\/application-host\/[A-Za-z0-9._/-]+/g)].map(
    ([reference]) => reference,
  );
  if (references.length === 0) return;
  if (!allowedDeploymentPath) {
    fail(`${origin} contains a deployment-specific publication path`);
  }

  const expectedPrefix = `/assets/application-host/${allowedDeploymentPath}/`;
  for (const reference of references) {
    if (!reference.startsWith(expectedPrefix)) {
      fail(`${origin} contains an unexpected deployment path ${JSON.stringify(reference)}`);
    }
  }
}

export async function validateFederationOutput(
  outputArgument,
  expectedRemoteName,
  { repositoryRootInput = repositoryRoot, requireExternal = true, allowedDeploymentPath } = {},
) {
  assertRemoteName(expectedRemoteName, "expected remote name");
  const canonicalRepositoryRoot = await realpath(repositoryRootInput).catch(() =>
    fail("repository root is unavailable"),
  );
  await assertOutputDirectory(outputArgument);
  const outputRoot = canonicalPathWithMissingTail(outputArgument);
  if (requireExternal) assertOutputOutsideRepository(outputRoot, canonicalRepositoryRoot);

  const paths = await outputFiles(outputRoot, outputRoot);
  if (paths.length === 0) fail("output is empty");

  const files = new Set(paths.map((path) => relativePath(outputRoot, path)));
  for (const path of files) assertReleaseArtifactPath(path);
  for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js"]) {
    if (!files.has(required)) fail(`missing required ${required}`);
  }
  if (!paths.some((path) => extname(path) === ".css")) fail("no CSS asset was emitted");

  const manifest = JSON.parse(await readFile(join(outputRoot, "mf-manifest.json"), "utf8"));
  const manifestReferences = assertGeneratedManifest(
    manifest,
    expectedRemoteName,
    files,
    outputRoot,
  );

  const stats = JSON.parse(await readFile(join(outputRoot, "mf-stats.json"), "utf8"));
  const statsReferences = assertStats(stats, files, outputRoot);
  for (const reference of manifestReferences) {
    if (!statsReferences.has(reference)) {
      fail(`manifest references ${JSON.stringify(reference)} missing from federation stats`);
    }
  }
  for (const path of files) {
    if (releaseMetadataFiles.has(path)) continue;
    if (!statsReferences.has(path)) {
      fail(`output contains an unreferenced or stale artifact ${JSON.stringify(path)}`);
    }
  }

  for (const path of paths) {
    const name = relativePath(outputRoot, path);
    const source = await readFile(path, "utf8").catch(() => null);
    if (source === null) continue;

    assertNoForbiddenPublicationReferences(source, name);
    assertDeploymentReferences(source, name, allowedDeploymentPath);

    if (/\.(?:js|mjs|cjs)$/i.test(name)) assertImportReferences(source, name, files, outputRoot);
    if (extname(name).toLowerCase() === ".css")
      assertCssReferences(source, name, files, outputRoot);
    if (extname(name).toLowerCase() === ".html")
      assertHtmlReferences(source, name, files, outputRoot);
  }

  return { outputRoot, fileCount: paths.length };
}

export async function validateReleaseOutput(
  outputArgument,
  expectedRemoteName,
  repositoryRootInput = repositoryRoot,
) {
  return validateFederationOutput(outputArgument, expectedRemoteName, {
    repositoryRootInput,
    requireExternal: true,
  });
}

export async function main(argumentsList = process.argv.slice(2)) {
  const outputArgument = parseOutputDirectoryArgument(argumentsList);
  const expectedRemoteName = parseRemoteNameArgument(argumentsList);
  const result = await validateReleaseOutput(outputArgument, expectedRemoteName);
  console.log(
    `Release output is relocatable: ${result.fileCount} files checked at ${result.outputRoot}`,
  );
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
