import { createHash } from "node:crypto";
import { lstatSync, realpathSync, statSync } from "node:fs";
import { lstat, readFile, readdir, realpath } from "node:fs/promises";
import {
  basename,
  dirname,
  extname,
  isAbsolute,
  join,
  relative,
  resolve,
  sep,
  win32,
} from "node:path";
import { fileURLToPath } from "node:url";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const remoteNamePattern = /^[a-z][a-z0-9._-]{0,127}$/;
const releaseMetadataFiles = new Set(["mf-manifest.json", "mf-stats.json"]);
const forbiddenArtifactNameSequences = [
  ["contract", "probe"],
  ["demo", "auth"],
  ["demo", "auth", "service"],
  ["failure", "application"],
  ["index"],
  ["main"],
  ["phoenix", "main"],
  ["phoenix", "bootstrap"],
  ["standalone"],
  ["spec"],
  ["test"],
];
const statsPathKeyPattern =
  /^(?:asset|assets|chunk|chunks|entry|entries|file|filename|fileName|output|outputs|paths|source|sources)$/i;
const generatedModuleFederationPathPattern =
  /^assets\/(?:dist|mf-entry-bootstrap|virtualExposes|virtual_mf|_virtual_mf|vite-preload-helper)-[A-Za-z0-9_.-]+\.js$/;

function fail(message) {
  throw new Error(`Release output check failed: ${message}`);
}

export function assertReleaseArtifactPath(path) {
  assertPathSyntax(path, "release artifact path");
  const lowerPath = path.toLowerCase();

  if (lowerPath.endsWith(".map")) fail(`source-map artifact ${JSON.stringify(path)} is forbidden`);
  if (lowerPath.endsWith(".html")) {
    fail(`standalone HTML artifact ${JSON.stringify(path)} is forbidden`);
  }
  assertNoForbiddenPathName(path, "release artifact path");
  if (!releaseMetadataFiles.has(path) && path !== "remoteEntry.js" && !path.startsWith("assets/")) {
    fail(`unexpected release artifact ${JSON.stringify(path)}`);
  }
}

function decodePathForPolicy(value, label) {
  if (!value.includes("%")) return value;
  let decoded;
  try {
    decoded = decodeURIComponent(value);
  } catch {
    fail(`${label} contains an invalid percent encoding`);
  }
  if (decoded.includes("%")) {
    fail(`${label} contains a doubly encoded or ambiguous path`);
  }
  return decoded;
}

function isAbsoluteLocalPath(value) {
  return (
    isAbsolute(value) ||
    win32.isAbsolute(value) ||
    /^[A-Za-z]:/.test(value) ||
    value.startsWith("\\") ||
    value.startsWith("file:")
  );
}

function isExternalReference(value) {
  return (
    value.startsWith("//") ||
    (/^(?:[a-z][a-z\d+.-]*:)/i.test(value) &&
      !/^[A-Za-z]:[\\/]/.test(value) &&
      !value.startsWith("file:"))
  );
}

function assertPathSyntax(value, label, { allowTraversal = false } = {}) {
  if (typeof value !== "string" || value.length === 0) fail(`${label} is not a path`);
  const decoded = decodePathForPolicy(value, label);
  if (decoded !== value) fail(`${label} contains URL-encoded/percent path syntax`);
  if (isAbsoluteLocalPath(value)) fail(`${label} must be relative`);
  if (value.includes("\\") || value.includes("\0")) {
    fail(`${label} contains a forbidden separator`);
  }
  const parts = value.split("/");
  if (
    parts.some(
      (part, index) =>
        part === "" || (!allowTraversal && part === "..") || (part === "." && index !== 0),
    )
  ) {
    fail(`${label} contains traversal or an empty path component`);
  }
}

function pathPolicyTokens(value, label) {
  const decoded = decodePathForPolicy(value, label).replaceAll("\\", "/");
  return decoded
    .split(/[^A-Za-z0-9]+/)
    .filter(Boolean)
    .map((token) => token.toLowerCase());
}

function hasSequence(tokens, sequence) {
  return tokens.some((_, index) =>
    sequence.every((token, offset) => tokens[index + offset] === token),
  );
}

function assertNoForbiddenPathName(value, label) {
  const tokens = pathPolicyTokens(value, label);
  if (forbiddenArtifactNameSequences.some((sequence) => hasSequence(tokens, sequence))) {
    fail(`standalone, test, or contract artifact ${JSON.stringify(value)} is forbidden`);
  }
}

export function assertNoForbiddenPublicationReferences(source, origin) {
  const forbiddenReferences = [
    ["demo-auth service", /\bdemo[-_]?auth(?:[-_]?service)?\b/i],
    [
      "contract probe",
      /(?:\bcontract[-_./\\]|contract%2d|contract%2e|contract%2f|contract%5c)+probe\b|cadence[._-]contract[._-]probe/i,
    ],
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
      const directoryName = relativePath(outputRoot, path);
      if (directoryName !== "assets") {
        fail(`output contains an unexpected or nested directory ${directoryName}`);
      }
      paths.push(...(await outputFiles(path, outputRoot)));
    } else if (entry.isFile()) {
      paths.push(path);
    } else {
      fail(`unsupported output entry ${relativePath(outputRoot, path)}`);
    }
  }

  return paths;
}

export function assertLocalReference(
  reference,
  origin,
  files,
  label,
  outputRoot,
  options = {},
) {
  const value = reference.trim();
  if (value === "" || /^\$\{[^}]+\}$/.test(value)) return;

  if (isExternalReference(value)) return;

  const pathPart =
    value.startsWith("?") || value.startsWith("#") ? origin : value.split(/[?#]/, 1)[0];
  if (pathPart === "") return;

  if (isAbsoluteLocalPath(pathPart)) {
    fail(`${label} contains an absolute local reference ${JSON.stringify(value)}`);
  }
  const authoritativeHostInitializationParent =
    options.authoritativeHostInitialization === true &&
    /^assets\/hostInit-[A-Za-z0-9_-]{8}\.js$/.test(origin) &&
    pathPart === "../remoteEntry.js";
  if (!authoritativeHostInitializationParent) assertPathSyntax(pathPart, label);
  assertNoForbiddenPathName(pathPart, label);

  const target = resolve(outputRoot, dirname(origin), pathPart);
  const targetRelative = relativePath(outputRoot, target);
  if (targetRelative === "" || targetRelative.startsWith("../") || targetRelative === "..") {
    fail(`${label} escapes the output with ${JSON.stringify(value)}`);
  }
  if (!files.has(targetRelative)) {
    fail(`${label} points to missing ${JSON.stringify(targetRelative)}`);
  }
  return targetRelative;
}

function assertManifestPath(value, files, label, outputRoot) {
  if (typeof value !== "string" || value.trim() === "") fail(`${label} is not a path`);
  const target = assertLocalReference(value, "mf-manifest.json", files, label, outputRoot);
  if (!target) fail(`${label} must be a local output path`);
  return target;
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
        const target = assertManifestPath(asset, files, `${label}.${kind}.${phase}`, outputRoot);
        referencedFiles?.add(target);
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
  const remoteEntryPath = assertManifestPath(
    remoteEntry.name,
    files,
    "manifest remoteEntry.name",
    outputRoot,
  );
  const referencedFiles = new Set([remoteEntryPath]);

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
    assertNoForbiddenPathName(exposedModule, "manifest exposed module");
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

function assertStatsMetadata(
  value,
  files,
  outputRoot,
  trail,
  pathContext = false,
  seen = new Set(),
  referencedFiles = new Set(),
) {
  if (typeof value === "string") {
    if (value.trim() === "") return;
    const decoded = value.includes("%") ? decodePathForPolicy(value, trail) : value;
    if (isAbsoluteLocalPath(value) || isAbsoluteLocalPath(decoded)) {
      fail(`${trail} contains an absolute local path ${JSON.stringify(value)}`);
    }
    if (isExternalReference(value)) return;
    assertNoForbiddenPathName(value, trail);
    if (
      pathContext ||
      value.includes("%") ||
      (/[/\\]/.test(decoded) && /\.[^/\\]+$/.test(decoded))
    ) {
      referencedFiles.add(assertManifestPath(value, files, trail, outputRoot));
    }
    return;
  }
  if (value === null || typeof value !== "object") return;
  if (seen.has(value)) fail(`${trail} contains a cyclic metadata value`);
  seen.add(value);
  if (Array.isArray(value)) {
    value.forEach((item, index) =>
      assertStatsMetadata(
        item,
        files,
        outputRoot,
        `${trail}[${index}]`,
        pathContext,
        seen,
        referencedFiles,
      ),
    );
  } else {
    for (const [key, child] of Object.entries(value)) {
      assertStatsMetadata(
        child,
        files,
        outputRoot,
        `${trail}.${key}`,
        pathContext || statsPathKeyPattern.test(key),
        seen,
        referencedFiles,
      );
    }
  }
  seen.delete(value);
}

function hasFederationStatsProvenance(stats, expectedRemoteName) {
  const metadata = stats.metaData;
  return (
    stats.id === expectedRemoteName &&
    stats.name === expectedRemoteName &&
    metadata &&
    typeof metadata === "object" &&
    metadata.name === expectedRemoteName &&
    metadata.remoteEntry &&
    metadata.remoteEntry.path === "" &&
    metadata.remoteEntry.name === "remoteEntry.js" &&
    metadata.remoteEntry.type === "module"
  );
}

const generatedHostInitializationPathPattern =
  /^assets\/hostInit-[A-Za-z0-9_-]{8}\.js$/;
const generatedHostInitializationFacadeDigests = new Set([
  "aa85d145c52d8de884e72e39705ac35f4141769062ba1ca6454cbadbfad153da",
  "add6febb13abf6c1923f431bbcf9aea1e282de287c64a4b7a0e8ee56768d61bc",
]);
const generatedFederationRuntimePathPattern = /^assets\/dist-[A-Za-z0-9_-]+\.js$/;
const generatedFederationRuntimeSourceDigests = new Set([
  "a38d94f4152a69a3b1b63c8afc9ebfa941681f1c32cda88ed07dc574dbd43a1e",
  "d6ce1afd105de3fda34eb27703b530dfb32d963a887a5f5297e0e154a4fc22f2",
]);

function canonicalHostInitializationSource(source, expectedRemoteName) {
  if (typeof source !== "string" || /(?:^|[^\\])\/(?:\/|\*)/.test(source)) return null;
  const escapedRemoteName = expectedRemoteName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expectedSharedImport = new RegExp(
    `_virtual_mf-localSharedImportMap___mfe_internal__${escapedRemoteName}__mf_owner__1-[A-Za-z0-9_-]{8}\\.js`,
  );
  if (!expectedSharedImport.test(source)) return null;
  return source
    .replace(/vite-preload-helper-[A-Za-z0-9_-]{8}\.js/g, "vite-preload-helper-<hash>.js")
    .replace(
      /_virtual_mf-localSharedImportMap___mfe_internal__[A-Za-z0-9._-]+__mf_owner__1-[A-Za-z0-9_-]{8}\.js/g,
      "_virtual_mf-localSharedImportMap___mfe_internal__<remote>__mf_owner__1-<hash>.js",
    )
    .replaceAll(expectedRemoteName, "<remote>")
    .replace(/\s+/g, "");
}

function isAuthoritativeGeneratedHostInitializationArtifact(
  name,
  source,
  stats,
  expectedRemoteName,
) {
  if (
    !generatedHostInitializationPathPattern.test(name) ||
    !hasFederationStatsProvenance(stats, expectedRemoteName)
  ) {
    return false;
  }
  const matchingRecords = stats.buildOutput.filter((output) => output?.fileName === name);
  if (matchingRecords.length !== 1) return false;
  const [record] = matchingRecords;
  if (
    record.type !== "chunk" ||
    record.isEntry !== false ||
    !Number.isSafeInteger(record.size) ||
    record.size < 0
  ) {
    return false;
  }
  if (
    record.facadeModuleId !== undefined &&
    (typeof record.facadeModuleId !== "string" || !/hostAutoInit|hostInit/i.test(record.facadeModuleId))
  ) {
    return false;
  }
  const canonical = canonicalHostInitializationSource(source, expectedRemoteName);
  return (
    canonical !== null &&
    generatedHostInitializationFacadeDigests.has(
      createHash("sha256").update(canonical, "utf8").digest("hex"),
    )
  );
}

function isGeneratedModuleFederationArtifactPath(path) {
  return generatedModuleFederationPathPattern.test(path);
}

function isAuthoritativeGeneratedFederationRuntimeArtifact(
  name,
  source,
  stats,
  expectedRemoteName,
) {
  if (
    !generatedFederationRuntimePathPattern.test(name) ||
    !hasFederationStatsProvenance(stats, expectedRemoteName)
  ) {
    return false;
  }
  const matchingRecords = stats.buildOutput.filter((output) => output?.fileName === name);
  if (matchingRecords.length !== 1) return false;
  const [record] = matchingRecords;
  return (
    record.type === "chunk" &&
    record.isEntry === false &&
    Number.isSafeInteger(record.size) &&
    record.size >= 0 &&
    typeof source === "string" &&
    generatedFederationRuntimeSourceDigests.has(
      createHash("sha256")
        .update(source.replace(/-[A-Za-z0-9_-]{8}\.js/g, "-<hash>.js"), "utf8")
        .digest("hex"),
    )
  );
}

function assertStats(stats, expectedRemoteName, files, outputRoot) {
  if (!Array.isArray(stats.buildOutput) || stats.buildOutput.length === 0) {
    fail("federation buildOutput is missing");
  }
  if (
    (stats.id !== undefined && stats.id !== expectedRemoteName) ||
    (stats.name !== undefined && stats.name !== expectedRemoteName) ||
    (stats.metaData?.name !== undefined && stats.metaData.name !== expectedRemoteName)
  ) {
    fail("federation stats identity is not the expected remote");
  }
  const referencedFiles = new Set();
  const buildOutputByPath = new Map();
  for (const output of stats.buildOutput) {
    if (!output || typeof output !== "object" || Array.isArray(output)) {
      fail("federation buildOutput entry is not an object");
    }
    const target = assertManifestPath(
      output.fileName,
      files,
      "federation buildOutput.fileName",
      outputRoot,
    );
    if (referencedFiles.has(target)) {
      fail(`federation stats contains duplicate artifact ${JSON.stringify(target)}`);
    }
    referencedFiles.add(target);
    buildOutputByPath.set(target, output);
  }
  assertStatsMetadata(
    stats,
    files,
    outputRoot,
    "federation stats",
    false,
    new Set(),
    referencedFiles,
  );
  const generatedModuleFederationFiles = new Set();
  if (hasFederationStatsProvenance(stats, expectedRemoteName)) {
    for (const [path, output] of buildOutputByPath) {
      if (
        isGeneratedModuleFederationArtifactPath(path) &&
        output.type === "chunk" &&
        output.isEntry === false &&
        Number.isSafeInteger(output.size) &&
        output.size >= 0
      ) {
        generatedModuleFederationFiles.add(path);
      }
    }
  }
  return {
    references: referencedFiles,
    generatedModuleFederationFiles,
  };
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

function javascriptTokens(source, origin = "JavaScript") {
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
      if (end === -1) fail(`${origin} contains an unterminated comment`);
      index = end + 2;
      continue;
    }
    if (character === "/" && canStartRegex(tokens)) {
      let inCharacterClass = false;
      let closed = false;
      index += 1;
      while (index < source.length) {
        const current = source[index];
        if (current === "\\") {
          index += 2;
          continue;
        }
        if (current === "[") inCharacterClass = true;
        if (current === "]") inCharacterClass = false;
        if (current === "/" && !inCharacterClass) {
          index += 1;
          while (/[A-Za-z]/.test(source[index] ?? "")) index += 1;
          closed = true;
          break;
        }
        index += 1;
      }
      if (!closed) fail(`${origin} contains an unterminated regular expression`);
      tokens.push({ kind: "regex", value: "regex" });
      continue;
    }
    if (character === "'" || character === '"' || character === "`") {
      const quote = character;
      const template = quote === "`";
      let value = "";
      let dynamic = false;
      let closed = false;
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
          closed = true;
          break;
        }
        value += current;
        index += 1;
      }
      if (!closed) fail(`${origin} contains an unterminated string or template`);
      tokens.push({
        kind: template ? "template" : "string",
        value,
        dynamic,
        dangerousDynamic:
          dynamic && /\b(?:import|new\s+URL|Worker|SharedWorker|ServiceWorker)\b/i.test(value),
      });
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

function canStartRegex(tokens) {
  const previous = tokens.at(-1);
  return (
    !previous ||
    previous.value === "(" ||
    previous.value === "[" ||
    previous.value === "{" ||
    previous.value === "," ||
    previous.value === ";" ||
    previous.value === ":" ||
    previous.value === "?" ||
    previous.value === "=" ||
    previous.value === "!" ||
    previous.value === "&" ||
    previous.value === "|" ||
    previous.value === "+" ||
    previous.value === "-" ||
    previous.value === "*" ||
    previous.value === "/" ||
    previous.value === "%" ||
    previous.value === "~" ||
    previous.value === "<" ||
    previous.value === ">" ||
    previous.value === "return" ||
    previous.value === "throw" ||
    previous.value === "case" ||
    previous.value === "=>"
  );
}

function isGeneratedEmptyFederationCssUrl(tokens, index) {
  const argument = tokens[index + 3];
  if (argument?.kind !== "word") return false;

  const callbackShape = [
    [index - 1, "="],
    [index - 2, "word"],
    [index - 3, "word"],
    [index - 4, "{"],
    [index - 5, ">"],
    [index - 6, "="],
    [index - 7, argument.value],
    [index - 8, "("],
    [index - 9, "map"],
    [index - 10, "."],
    [index - 11, "word"],
  ];
  if (
    callbackShape.some(([tokenIndex, expected]) => {
      const token = tokens[tokenIndex];
      return expected === "word"
        ? token?.kind !== "word"
        : token?.value !== expected;
    })
  ) {
    return false;
  }

  const mappedSource = tokens[index - 11].value;
  for (let cursor = 0; cursor < index - 11; cursor += 1) {
    if (
      tokens[cursor]?.value === "let" &&
      tokens[cursor + 1]?.value === mappedSource &&
      tokens[cursor + 2]?.value === "=" &&
      tokens[cursor + 3]?.value === "t" &&
      tokens[cursor + 4]?.value === "[" &&
      tokens[cursor + 5]?.value === argument.value &&
      tokens[cursor + 6]?.value === "]" &&
      tokens[cursor + 7]?.value === "|" &&
      tokens[cursor + 8]?.value === "|" &&
      tokens[cursor + 9]?.value === "[" &&
      tokens[cursor + 10]?.value === "]"
    ) {
      for (let declaration = 0; declaration < cursor; declaration += 1) {
        if (
          tokens[declaration]?.value === "var" &&
          tokens[declaration + 1]?.value === "t" &&
          tokens[declaration + 2]?.value === "=" &&
          tokens[declaration + 3]?.value === "{" &&
          tokens[declaration + 4]?.value === "}"
        ) {
          return true;
        }
      }
    }
  }
  return false;
}

function isGeneratedVitePreloadUrl(tokens, index) {
  const argument = tokens[index + 3];
  const expected = [
    [index - 1, ":"],
    [index - 2, ")"],
    [index - 3, argument?.value],
    [index - 4, "("],
    [index - 5, "resolve"],
    [index - 6, "."],
    [index - 7, "meta"],
    [index - 8, "."],
    [index - 9, "import"],
    [index - 10, "?"],
    [index - 11, "resolve"],
    [index - 12, "."],
    [index - 13, "meta"],
    [index - 14, "."],
    [index - 15, "import"],
    [index - 16, "return"],
    [index - 17, "{"],
    [index - 18, ")"],
    [index - 19, argument?.value],
    [index - 20, "("],
    [index - 21, "word"],
    [index - 22, "function"],
  ];
  if (argument?.kind !== "word") return false;
  return expected.every(([tokenIndex, value]) => {
    const token = tokens[tokenIndex];
    return value === "word" ? token?.kind === "word" : token?.value === value;
  });
}

function isGeneratedVitePreloadHelperUrl(tokens, index) {
  return (
    tokens[index - 11]?.value === "var" &&
    tokens[index - 10]?.kind === "word" &&
    tokens[index - 9]?.value === "=" &&
    tokens[index - 8]?.value === "function" &&
    tokens[index - 7]?.value === "(" &&
    tokens[index - 6]?.kind === "word" &&
    tokens[index - 5]?.value === "," &&
    tokens[index - 4]?.kind === "word" &&
    tokens[index - 3]?.value === ")" &&
    tokens[index - 2]?.value === "{" &&
    tokens[index - 1]?.value === "return" &&
    tokens[index + 3]?.kind === "word" &&
    tokens[index + 5]?.kind === "word" &&
    tokens[index - 10]?.value === tokens[index + 3]?.value &&
    tokens[index - 4]?.value === tokens[index + 5]?.value &&
    tokens[index + 4]?.value === "," &&
    tokens[index + 6]?.value === ")" &&
    tokens[index + 7]?.value === "." &&
    tokens[index + 8]?.value === "href" &&
    tokens[index + 9]?.value === "}"
  );
}

function isGeneratedFederationRemoteImport(tokens, index) {
  const argument = tokens[index + 2];
  const expected = [
    [index - 1, ">"],
    [index - 2, "="],
    [index - 3, ")"],
    [index - 4, "("],
    [index - 5, "("],
    [index - 6, "word"],
    [index + 3, ")"],
    [index + 4, "."],
    [index + 5, "then"],
    [index + 6, "("],
    [index + 7, "word"],
    [index + 8, ")"],
    [index + 9, ","],
    [index + 10, "["],
    [index + 11, "]"],
    [index + 12, ","],
    [index + 13, "import"],
    [index + 14, "."],
    [index + 15, "meta"],
    [index + 16, "."],
    [index + 17, "url"],
  ];
  if (argument?.kind !== "word") return false;
  return expected.every(([tokenIndex, value]) => {
    const token = tokens[tokenIndex];
    return value === "word" ? token?.kind === "word" : token?.value === value;
  });
}

function isGeneratedFederationRemoteImportWithoutImportMeta(tokens, index) {
  const argument = tokens[index + 2];
  const expected = [
    [index - 1, ">"],
    [index - 2, "="],
    [index - 3, ")"],
    [index - 4, "("],
    [index - 5, "("],
    [index - 6, "word"],
    [index + 3, ")"],
    [index + 4, "."],
    [index + 5, "then"],
    [index + 6, "("],
    [index + 7, "word"],
    [index + 8, ")"],
    [index + 9, ","],
    [index + 10, "["],
    [index + 11, "]"],
    [index + 12, ")"],
    [index + 13, "."],
    [index + 14, "catch"],
    [index + 15, "("],
    [index + 16, "word"],
    [index + 17, ")"],
  ];
  if (argument?.kind !== "word") return false;
  return expected.every(([tokenIndex, value]) => {
    const token = tokens[tokenIndex];
    return value === "word" ? token?.kind === "word" : token?.value === value;
  });
}

function isGeneratedFederationExternalImport(tokens, index) {
  const argument = tokens[index + 2];
  const expected = [
    [index - 1, ":"],
    [index + 3, ")"],
    [index + 4, "."],
    [index + 5, "then"],
    [index + 6, "("],
    [index + 7, "word"],
    [index + 8, ")"],
    [index + 9, "."],
    [index + 10, "catch"],
    [index + 11, "("],
    [index + 12, "word"],
    [index + 13, ")"],
  ];
  if (argument?.kind !== "word") return false;
  if (
    !expected.every(([tokenIndex, value]) => {
      const token = tokens[tokenIndex];
      return value === "word" ? token?.kind === "word" : token?.value === value;
    })
  ) {
    return false;
  }
  return true;
}

const workerConstructorNames = new Set(["Worker", "SharedWorker", "ServiceWorker"]);

function workerCallAt(tokens, index) {
  const token = tokens[index];
  const next = tokens[index + 1];
  const globalWorkerOwners = new Set(["globalThis", "self", "window"]);
  if (
    token?.kind === "word" &&
    token.value === "new" &&
    workerConstructorNames.has(next?.value) &&
    tokens[index + 2]?.value === "("
  ) {
    return { argument: index + 3 };
  }
  if (
    token?.kind === "word" &&
    token.value === "new" &&
    globalWorkerOwners.has(next?.value) &&
    tokens[index + 2]?.value === "." &&
    workerConstructorNames.has(tokens[index + 3]?.value) &&
    tokens[index + 4]?.value === "("
  ) {
    return { argument: index + 5 };
  }
  if (
    token?.kind === "word" &&
    token.value === "new" &&
    tokens[index + 1]?.value === "(" &&
    workerConstructorNames.has(tokens[index + 2]?.value) &&
    tokens[index + 3]?.value === ")" &&
    tokens[index + 4]?.value === "("
  ) {
    return { argument: index + 5 };
  }
  if (
    token?.kind === "word" &&
    workerConstructorNames.has(token.value) &&
    next?.value === "(" &&
    (tokens[index - 1]?.value !== "." ||
      globalWorkerOwners.has(tokens[index - 2]?.value))
  ) {
    return { argument: index + 2 };
  }
  if (
    token?.kind === "word" &&
    token.value === "register" &&
    tokens[index - 1]?.value === "." &&
    tokens[index - 2]?.value === "serviceWorker" &&
    next?.value === "("
  ) {
    return { argument: index + 2 };
  }
  return null;
}

function isStaticImportMetaUrlCall(tokens, index) {
  return (
    staticReferenceToken(tokens[index + 3]) &&
    tokens[index + 4]?.value === "," &&
    tokens[index + 5]?.value === "import" &&
    tokens[index + 6]?.value === "." &&
    tokens[index + 7]?.value === "meta" &&
    tokens[index + 8]?.value === "." &&
    tokens[index + 9]?.value === "url" &&
    tokens[index + 10]?.value === ")"
  );
}

function isGeneratedViteDynamicAssetUrl(tokens, index) {
  return (
    tokens[index + 3]?.kind === "string" &&
    tokens[index + 4]?.value === "+" &&
    tokens[index + 5]?.kind === "word" &&
    tokens[index + 6]?.value === "," &&
    tokens[index + 7]?.value === "import" &&
    tokens[index + 8]?.value === "." &&
    tokens[index + 9]?.value === "meta" &&
    tokens[index + 10]?.value === "." &&
    tokens[index + 11]?.value === "url" &&
    tokens[index + 12]?.value === ")"
  );
}

function isGeneratedRuntimeUrl(tokens, index) {
  const directEntry =
    tokens[index + 3]?.kind === "word" &&
    tokens[index + 4]?.value === "," &&
    tokens[index + 5]?.value === "window" &&
    tokens[index + 6]?.value === "." &&
    tokens[index + 7]?.value === "location" &&
    tokens[index + 8]?.value === "." &&
    tokens[index + 9]?.value === "origin" &&
    tokens[index + 10]?.value === ")";
  const memberEntry =
    tokens[index + 3]?.kind === "word" &&
    tokens[index + 4]?.value === "." &&
    tokens[index + 5]?.value === "entry" &&
    tokens[index + 6]?.value === "," &&
    tokens[index + 7]?.value === "window" &&
    tokens[index + 8]?.value === "." &&
    tokens[index + 9]?.value === "location" &&
    tokens[index + 10]?.value === "." &&
    tokens[index + 11]?.value === "origin" &&
    tokens[index + 12]?.value === ")";
  return directEntry || memberEntry;
}

function isGeneratedFederationDynamicTemplate(token) {
  return (
    token?.kind === "template" &&
    token.dynamic === true &&
    /^\s*(?:System\.)?import\("\$\{[A-Za-z_$][A-Za-z0-9_$]*\}"\)\$\{[A-Za-z_$][A-Za-z0-9_$]*\}\s*$/.test(
      token.value,
    )
  );
}

export function assertImportReferences(
  source,
  origin,
  files,
  outputRoot,
  referencedFiles = new Set(),
  options = {},
) {
  const tokens = javascriptTokens(source, origin);
  const generatedModuleFederation = options.generatedModuleFederation === true;
  const authoritativeDynamicImport =
    options.authoritativeGeneratedDynamicImport === true ||
    options.authoritativeHostPublication === true;
  if (
    tokens.some(
      (token) =>
        token.dangerousDynamic &&
        (!authoritativeDynamicImport || !isGeneratedFederationDynamicTemplate(token)),
    )
  ) {
    fail(`${origin} contains an unresolved dynamic template expression`);
  }
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    const next = tokens[index + 1];

    if (
      token.kind === "word" &&
      token.value === "from" &&
      !isMemberProperty(tokens, index) &&
      staticReferenceToken(next)
    ) {
      const target = assertLocalReference(
        next.value,
        origin,
        files,
        `${origin} import`,
        outputRoot,
        options,
      );
      if (target) referencedFiles.add(target);
      continue;
    }

    if (token.kind === "word" && token.value === "import" && !isMemberProperty(tokens, index)) {
      if (staticReferenceToken(next)) {
        const target = assertLocalReference(
          next.value,
          origin,
          files,
          `${origin} import`,
          outputRoot,
          options,
        );
        if (target) referencedFiles.add(target);
        continue;
      }
      if (next?.value === "(") {
        if (
          staticReferenceToken(tokens[index + 2]) &&
          tokens[index + 3]?.value === ")"
        ) {
          const target = assertLocalReference(
            tokens[index + 2].value,
            origin,
            files,
            `${origin} import`,
            outputRoot,
            options,
          );
          if (target) referencedFiles.add(target);
        } else if (
          authoritativeDynamicImport &&
          (isGeneratedFederationRemoteImport(tokens, index) ||
            isGeneratedFederationRemoteImportWithoutImportMeta(tokens, index) ||
            (options.authoritativeHostPublication === true &&
              isGeneratedFederationExternalImport(tokens, index)))
        ) {
          continue;
        } else {
          fail(`${origin} contains an unresolved dynamic local import`);
        }
      }
      continue;
    }

    const workerCall = workerCallAt(tokens, index);
    if (workerCall) {
      const argument = tokens[workerCall.argument];
      if (
        staticReferenceToken(argument) &&
        [")", ","].includes(tokens[workerCall.argument + 1]?.value)
      ) {
        const target = assertLocalReference(
          argument.value,
          origin,
          files,
          `${origin} worker URL`,
          outputRoot,
          options,
        );
        if (target) referencedFiles.add(target);
      } else if (
        argument?.value === "new" &&
        tokens[workerCall.argument + 1]?.value === "URL" &&
        tokens[workerCall.argument + 2]?.value === "(" &&
        isStaticImportMetaUrlCall(tokens, workerCall.argument)
      ) {
        const target = assertLocalReference(
          tokens[workerCall.argument + 3].value,
          origin,
          files,
          `${origin} worker URL`,
          outputRoot,
          options,
        );
        if (target) referencedFiles.add(target);
      } else {
        fail(`${origin} contains an unresolved dynamic worker URL`);
      }
      continue;
    }

    if (
      token.kind === "word" &&
      token.value === "new" &&
      tokens[index + 1]?.value === "URL" &&
      tokens[index + 2]?.value === "(" &&
      isStaticImportMetaUrlCall(tokens, index)
    ) {
      const target = assertLocalReference(
        tokens[index + 3].value,
        origin,
        files,
        `${origin} asset URL`,
        outputRoot,
        options,
      );
      if (target) referencedFiles.add(target);
      continue;
    }

    if (
      token.kind === "word" &&
      token.value === "new" &&
      tokens[index + 1]?.value === "URL" &&
      tokens[index + 2]?.value === "("
    ) {
      if (
        options.authoritativeHostPublication === true ||
        (generatedModuleFederation &&
          (isGeneratedEmptyFederationCssUrl(tokens, index) ||
            isGeneratedVitePreloadUrl(tokens, index) ||
            isGeneratedVitePreloadHelperUrl(tokens, index) ||
            isGeneratedViteDynamicAssetUrl(tokens, index) ||
            isGeneratedRuntimeUrl(tokens, index)))
      ) {
        continue;
      }
      if (
        staticReferenceToken(tokens[index + 3]) &&
        isExternalReference(tokens[index + 3].value)
      ) {
        continue;
      }
      fail(`${origin} contains an unresolved dynamic local asset URL`);
    }
  }
  return referencedFiles;
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

export function assertCssReferences(
  source,
  origin,
  files,
  outputRoot,
  referencedFiles = new Set(),
) {
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
          const target = assertLocalReference(
            url.value,
            origin,
            files,
            `${origin} CSS import`,
            outputRoot,
          );
          if (target) referencedFiles.add(target);
          index = url.next;
          continue;
        }
        if (source[next] === "'" || source[next] === '"') {
          const imported = readCssString(source, next);
          const target = assertLocalReference(
            imported.value,
            origin,
            files,
            `${origin} CSS import`,
            outputRoot,
          );
          if (target) referencedFiles.add(target);
          index = imported.next;
          continue;
        }
      }
    }

    const url = readCssUrlFunction(source, index);
    if (url) {
      const target = assertLocalReference(
        url.value,
        origin,
        files,
        `${origin} CSS URL`,
        outputRoot,
      );
      if (target) referencedFiles.add(target);
      index = url.next;
      continue;
    }

    index += 1;
  }
  return referencedFiles;
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

function snapshotOutputFiles(snapshot, outputRoot) {
  if (!snapshot || !Array.isArray(snapshot.artifacts)) {
    fail("artifact snapshot is invalid");
  }
  const byName = new Map();
  for (const artifact of snapshot.artifacts) {
    if (!artifact || typeof artifact.path !== "string" || !Buffer.isBuffer(artifact.bytes)) {
      fail("artifact snapshot entry is invalid");
    }
    assertReleaseArtifactPath(artifact.path);
    if (byName.has(artifact.path)) {
      fail(`artifact snapshot contains duplicate ${JSON.stringify(artifact.path)}`);
    }
    byName.set(artifact.path, artifact);
  }
  const names = [...byName.keys()].sort((left, right) => left.localeCompare(right));
  return {
    files: new Set(names),
    names,
    paths: names.map((name) => join(outputRoot, ...name.split("/"))),
    readText: async (name) => byName.get(name)?.bytes.toString("utf8") ?? null,
  };
}

function assertDeploymentReferences(source, origin, allowedDeploymentPath) {
  const deploymentMarker = "/assets/application-host";
  const references = [
    ...source.matchAll(/\/assets\/application-host[^\s"'`),;?}]*/g),
  ].map(([reference]) => reference);
  if (references.length === 0) return;
  if (!allowedDeploymentPath) {
    fail(`${origin} contains a deployment-specific publication path`);
  }

  assertPathSyntax(allowedDeploymentPath, "allowed deployment path");
  for (const reference of references) {
    const deploymentPath = reference.slice(deploymentMarker.length + 1);
    if (!deploymentPath || deploymentPath.split("/")[0] !== allowedDeploymentPath) {
      fail(`${origin} contains an unexpected deployment path ${JSON.stringify(reference)}`);
    }
    assertPathSyntax(deploymentPath, `${origin} deployment path`);
    if (deploymentPath.split("/").length < 2) {
      fail(`${origin} contains an incomplete deployment path ${JSON.stringify(reference)}`);
    }
  }
}

export async function validateFederationOutput(
  outputArgument,
  expectedRemoteName,
  {
    repositoryRootInput = repositoryRoot,
    requireExternal = true,
    allowedDeploymentPath,
    artifactSnapshot,
  } = {},
) {
  assertRemoteName(expectedRemoteName, "expected remote name");
  const canonicalRepositoryRoot = await realpath(repositoryRootInput).catch(() =>
    fail("repository root is unavailable"),
  );
  await assertOutputDirectory(outputArgument);
  const outputRoot = canonicalPathWithMissingTail(outputArgument);
  if (requireExternal) assertOutputOutsideRepository(outputRoot, canonicalRepositoryRoot);
  if (artifactSnapshot) {
    if (typeof artifactSnapshot.root !== "string") fail("artifact snapshot root is invalid");
    if (canonicalPathWithMissingTail(artifactSnapshot.root) !== outputRoot) {
      fail("artifact snapshot root does not match the output directory");
    }
  }

  const snapshot = artifactSnapshot
    ? snapshotOutputFiles(artifactSnapshot, outputRoot)
    : {
        paths: await outputFiles(outputRoot, outputRoot),
        readText: async (name) =>
          readFile(join(outputRoot, ...name.split("/")), "utf8").catch(() => null),
      };
  const paths = snapshot.paths;
  if (paths.length === 0) fail("output is empty");

  const files = snapshot.files ?? new Set(paths.map((path) => relativePath(outputRoot, path)));
  for (const path of files) assertReleaseArtifactPath(path);
  for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js"]) {
    if (!files.has(required)) fail(`missing required ${required}`);
  }
  if (!paths.some((path) => extname(path) === ".css")) fail("no CSS asset was emitted");

  const manifest = JSON.parse(await snapshot.readText("mf-manifest.json"));
  const manifestReferences = assertGeneratedManifest(
    manifest,
    expectedRemoteName,
    files,
    outputRoot,
  );

  const stats = JSON.parse(await snapshot.readText("mf-stats.json"));
  const statsResult = assertStats(stats, expectedRemoteName, files, outputRoot);
  const statsReferences = statsResult.references;
  const generatedModuleFederationFiles = statsResult.generatedModuleFederationFiles;

  const manifestClosure = new Set(manifestReferences);
  const pending = [...manifestClosure];
  const visited = new Set();
  while (pending.length > 0) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    const source = await snapshot.readText(name);
    if (source === null) fail(`manifest closure cannot read ${JSON.stringify(name)}`);
    const discovered = new Set();
    const generatedModuleFederation =
      generatedModuleFederationFiles.has(name) && manifestClosure.has(name);
    const authoritativeGeneratedDynamicImport =
      generatedModuleFederation &&
      isAuthoritativeGeneratedFederationRuntimeArtifact(
        name,
        source,
        stats,
        expectedRemoteName,
      );
    if (/\.(?:js|mjs|cjs)$/i.test(name)) {
      assertImportReferences(source, name, files, outputRoot, discovered, {
        generatedModuleFederation,
        authoritativeGeneratedDynamicImport,
      });
    }
    if (extname(name).toLowerCase() === ".css") {
      assertCssReferences(source, name, files, outputRoot, discovered);
    }
    for (const reference of discovered) {
      if (!manifestClosure.has(reference)) {
        manifestClosure.add(reference);
        pending.push(reference);
      }
    }
  }

  for (const reference of manifestClosure) {
    if (!statsReferences.has(reference)) {
      fail(`manifest references ${JSON.stringify(reference)} missing from federation stats`);
    }
  }
  for (const reference of statsReferences) {
    if (!manifestClosure.has(reference)) {
      const source = await snapshot.readText(reference);
      if (
        !isAuthoritativeGeneratedHostInitializationArtifact(
          reference,
          source,
          stats,
          expectedRemoteName,
        )
      ) {
        fail(`federation stats references ${JSON.stringify(reference)} missing from manifest closure`);
      }
      const discovered = new Set();
      assertImportReferences(
        source,
        reference,
        files,
        outputRoot,
        discovered,
        { authoritativeHostInitialization: true },
      );
      for (const target of discovered) {
        if (!manifestClosure.has(target)) {
          fail(
            `generated host initialization ${JSON.stringify(reference)} references ${JSON.stringify(target)} outside manifest closure`,
          );
        }
      }
      manifestClosure.add(reference);
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
    const source = await snapshot.readText(name);
    if (source === null) continue;

    assertNoForbiddenPublicationReferences(source, name);
    assertDeploymentReferences(source, name, allowedDeploymentPath);

    if (/\.(?:js|mjs|cjs)$/i.test(name)) {
      const generatedModuleFederation =
        generatedModuleFederationFiles.has(name) && manifestClosure.has(name);
      assertImportReferences(source, name, files, outputRoot, new Set(), {
        generatedModuleFederation,
        authoritativeGeneratedDynamicImport:
          generatedModuleFederation &&
          isAuthoritativeGeneratedFederationRuntimeArtifact(
            name,
            source,
            stats,
            expectedRemoteName,
          ),
        authoritativeHostInitialization:
          generatedHostInitializationPathPattern.test(name) &&
          isAuthoritativeGeneratedHostInitializationArtifact(
            name,
            source,
            stats,
            expectedRemoteName,
          ),
      });
    }
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
  options = {},
) {
  return validateFederationOutput(outputArgument, expectedRemoteName, {
    repositoryRootInput,
    requireExternal: true,
    ...options,
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
