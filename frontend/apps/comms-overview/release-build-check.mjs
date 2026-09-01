import { readFile, readdir, realpath } from "node:fs/promises";
import { dirname, extname, isAbsolute, join, relative, resolve, sep } from "node:path";

const outputArgument = process.argv[2];
const repositoryRoot = resolve(import.meta.dirname, "../../..");

function fail(message) {
  throw new Error(`Release output check failed: ${message}`);
}

if (!outputArgument || !isAbsolute(outputArgument)) {
  fail("an absolute output directory outside the repository is required");
}

let outputRoot = "";

function relativePath(path) {
  return relative(outputRoot, path).split(sep).join("/");
}

async function outputFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  const paths = [];

  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) {
      paths.push(...(await outputFiles(path)));
    } else if (entry.isFile()) {
      paths.push(path);
    } else {
      fail(`unsupported output entry ${relativePath(path)}`);
    }
  }

  return paths;
}

function assertLocalReference(reference, origin, files, label) {
  const value = reference.trim();
  if (
    value === "" ||
    value.startsWith("#") ||
    value.startsWith("data:") ||
    /^\$\{[^}]+\}$/.test(value)
  )
    return;
  if (/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(value) || value.startsWith("/")) {
    fail(`${label} contains an absolute reference ${JSON.stringify(value)}`);
  }

  const withoutFragment = value.split(/[?#]/, 1)[0];
  const target = resolve(outputRoot, dirname(origin), withoutFragment);
  const targetRelative = relativePath(target);
  if (targetRelative === "" || targetRelative.startsWith("../") || targetRelative === "..") {
    fail(`${label} escapes the output with ${JSON.stringify(value)}`);
  }
  if (!files.has(targetRelative)) {
    fail(`${label} points to missing ${JSON.stringify(targetRelative)}`);
  }
}

function assertManifestPath(value, files, label) {
  if (typeof value !== "string" || value.trim() === "") fail(`${label} is not a path`);
  assertLocalReference(value, "mf-manifest.json", files, label);
}

function assertAssetLists(value, files, label) {
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
        assertManifestPath(asset, files, `${label}.${kind}.${phase}`);
      }
    }
  }
}

function assertGeneratedManifest(manifest, files) {
  if (manifest.id !== "cadence_comms_overview" || manifest.name !== "cadence_comms_overview") {
    fail("the federation manifest identity is not cadence_comms_overview");
  }

  const metadata = manifest.metaData;
  if (!metadata || typeof metadata !== "object") fail("manifest metadata is missing");
  if (metadata.publicPath !== "auto")
    fail(`manifest publicPath is ${JSON.stringify(metadata.publicPath)}`);

  const remoteEntry = metadata.remoteEntry;
  if (!remoteEntry || remoteEntry.path !== "" || remoteEntry.name !== "remoteEntry.js") {
    fail("manifest remoteEntry is not the relocatable remoteEntry.js");
  }
  assertManifestPath(remoteEntry.name, files, "manifest remoteEntry.name");

  if (!Array.isArray(manifest.shared) || manifest.shared.length === 0) {
    fail("manifest shared assets are missing");
  }
  for (const shared of manifest.shared) {
    assertAssetLists(shared.assets, files, `manifest shared ${shared.name}`);
  }

  if (!Array.isArray(manifest.exposes) || manifest.exposes.length === 0) {
    fail("manifest exposes are missing");
  }
  for (const expose of manifest.exposes) {
    assertAssetLists(expose.assets, files, `manifest expose ${expose.name}`);
  }
}

function assertStats(stats, files) {
  if (!Array.isArray(stats.buildOutput) || stats.buildOutput.length === 0) {
    fail("federation buildOutput is missing");
  }
  for (const output of stats.buildOutput) {
    assertManifestPath(output.fileName, files, "federation buildOutput.fileName");
  }
}

function assertJsonManifestReferences(value, files, label) {
  if (!value || typeof value !== "object") return;
  if (Array.isArray(value)) {
    for (const item of value) assertJsonManifestReferences(item, files, label);
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (["file", "css", "assets"].includes(key)) {
      const references = Array.isArray(child) ? child : [child];
      for (const reference of references) {
        assertManifestPath(reference, files, `${label}.${key}`);
      }
    } else {
      assertJsonManifestReferences(child, files, `${label}.${key}`);
    }
  }
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

function assertImportReferences(source, origin, files) {
  const tokens = javascriptTokens(source);
  for (let index = 0; index < tokens.length; index += 1) {
    const token = tokens[index];
    const next = tokens[index + 1];

    if (token.kind === "word" && token.value === "from" && staticReferenceToken(next)) {
      assertLocalReference(next.value, origin, files, `${origin} import`);
      continue;
    }

    if (token.kind === "word" && token.value === "import") {
      if (staticReferenceToken(next)) {
        assertLocalReference(next.value, origin, files, `${origin} import`);
        continue;
      }
      if (
        next?.value === "(" &&
        staticReferenceToken(tokens[index + 2]) &&
        tokens[index + 3]?.value === ")"
      ) {
        assertLocalReference(tokens[index + 2].value, origin, files, `${origin} import`);
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
      assertLocalReference(tokens[index + 3].value, origin, files, `${origin} asset URL`);
    }
  }
}

function assertCssReferences(source, origin, files) {
  const urlPattern = /url\(\s*(?:"([^"]+)"|'([^']+)'|([^\s)]+))\s*\)/gi;
  for (const match of source.matchAll(urlPattern)) {
    const reference = match[1] ?? match[2] ?? match[3];
    if (reference !== undefined)
      assertLocalReference(reference, origin, files, `${origin} CSS URL`);
  }

  const importPattern = /@import\s+(?:url\(\s*)?(?:"([^"]+)"|'([^']+)'|([^\s;)'"]+))/gi;
  for (const match of source.matchAll(importPattern)) {
    const reference = match[1] ?? match[2] ?? match[3];
    if (reference !== undefined)
      assertLocalReference(reference, origin, files, `${origin} CSS import`);
  }
}

function assertHtmlReferences(source, origin, files) {
  const attributePattern = /\b(?:src|href)\s*=\s*["']([^"']+)["']/gi;
  for (const match of source.matchAll(attributePattern)) {
    assertLocalReference(match[1], origin, files, `${origin} HTML reference`);
  }
}

async function main() {
  const canonicalRepositoryRoot = await realpath(repositoryRoot).catch(() =>
    fail("repository root is unavailable"),
  );
  outputRoot = await realpath(outputArgument).catch(() => fail("output directory is unavailable"));
  const repositoryRelative = relative(canonicalRepositoryRoot, outputRoot);
  if (
    repositoryRelative === "" ||
    (!repositoryRelative.startsWith(`..${sep}`) &&
      repositoryRelative !== ".." &&
      !isAbsolute(repositoryRelative))
  ) {
    fail("output directory must be outside the repository");
  }

  const paths = await outputFiles(outputRoot);
  if (paths.length === 0) fail("output is empty");

  const files = new Set(paths.map(relativePath));
  for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js", "index.html"]) {
    if (!files.has(required)) fail(`missing required ${required}`);
  }
  if (!paths.some((path) => extname(path) === ".css")) fail("no CSS asset was emitted");
  if (!paths.some((path) => /\.(?:woff2?|ttf|otf)$/i.test(path))) {
    fail("no font asset was emitted");
  }

  const manifest = JSON.parse(await readFile(join(outputRoot, "mf-manifest.json"), "utf8"));
  assertGeneratedManifest(manifest, files);

  const stats = JSON.parse(await readFile(join(outputRoot, "mf-stats.json"), "utf8"));
  assertStats(stats, files);

  const viteManifestPath = join(outputRoot, ".vite/manifest.json");
  if (files.has(".vite/manifest.json")) {
    const viteManifest = JSON.parse(await readFile(viteManifestPath, "utf8"));
    assertJsonManifestReferences(viteManifest, files, ".vite/manifest");
  }

  for (const path of paths) {
    const name = relativePath(path);
    const source = await readFile(path, "utf8").catch(() => null);
    if (source === null) continue;

    if (/\.(?:js|mjs|cjs)$/i.test(name)) assertImportReferences(source, name, files);
    if (extname(name).toLowerCase() === ".css") assertCssReferences(source, name, files);
    if (extname(name).toLowerCase() === ".html") assertHtmlReferences(source, name, files);

    if (/\/assets\/application-host\/|\/releases\/|artifactBaseUrl|MF_BUILD_VERSION/.test(source)) {
      fail(`${name} contains a deployment-specific path or build-version marker`);
    }
  }

  console.log(`Release output is relocatable: ${paths.length} files checked at ${outputRoot}`);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exitCode = 1;
});
