import assert from "node:assert/strict";
import { createHash as nodeCreateHash } from "node:crypto";
import { lstat, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { spawn } from "node:child_process";
import test from "node:test";
import { tmpdir } from "node:os";
import { Script } from "node:vm";
import { basename, join, posix, resolve } from "node:path";
import { transformWithEsbuild } from "vite";

const appRoot = resolve(import.meta.dirname);
const vitePlusEntry = resolve(appRoot, "node_modules/vite-plus/bin/vp");

async function withTemporaryDirectory(callback) {
  const directory = await mkdtemp(join(tmpdir(), "cadence-comms-release-config-"));
  try {
    return await callback(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function runVite(argumentsList, environment = {}) {
  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, [vitePlusEntry, ...argumentsList], {
      cwd: appRoot,
      env: {
        ...process.env,
        ...environment,
        PATH: `${resolve(process.execPath, "..")}:${process.env.PATH ?? ""}`,
      },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.once("error", reject);
    child.once("close", (code, signal) =>
      resolveResult({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      }),
    );
  });
}

async function outputFiles(root) {
  const entries = await readdir(root, { withFileTypes: true });
  const files = [];
  for (const entry of entries.sort((left, right) => left.name.localeCompare(right.name))) {
    const path = join(root, entry.name);
    if (entry.isDirectory()) files.push(...(await outputFiles(path)));
    else if (entry.isFile()) files.push(path);
  }
  return files;
}

function releaseArguments(output) {
  return [
    "build",
    "--config",
    resolve(appRoot, "vite.config.ts"),
    "--mode",
    "release",
    "--outDir",
    output,
  ];
}

const exactHostInitializationFacadeId =
  "\0virtual:mf:__mfe_internal__cadence_comms_overview__mf_owner__1__H_A_I__hostAutoInit__H_A_I__.js";
const generatedHostInitializationDigest =
  "e25074ccfca4c766e209adf9e7529680fcca051c844fa5d6d6c1a8e139601068";
const hostInitializationHash = "ZYXWVUTS";
const hostInitializationPath = `assets/hostInit-${hostInitializationHash}.js`;
const hostInitializationSource = [
  `import"./vite-preload-helper-${hostInitializationHash}.js";`,
  `import"./_virtual_mf-localSharedImportMap___mfe_internal__cadence_comms_overview__mf_owner__1-${hostInitializationHash}.js";`,
  "var t=`__mf_module_cache__`;function loadShare(){}export{t as hostInitPromise,loadShare as initHost};",
].join("");
const canonicalHostInitializationSource = hostInitializationSource
  .replace(/vite-preload-helper-[A-Za-z0-9_-]{8}\.js/g, "vite-preload-helper-<hash>.js")
  .replace(
    /_virtual_mf-localSharedImportMap___mfe_internal__[A-Za-z0-9._-]+__mf_owner__1-[A-Za-z0-9_-]{8}\.js/g,
    "_virtual_mf-localSharedImportMap___mfe_internal__<remote>__mf_owner__1-<hash>.js",
  )
  .replaceAll("cadence_comms_overview", "<remote>")
  .replace(/\s+/g, "");

let releaseOutputPluginPromise;

async function releaseOutputPlugin() {
  releaseOutputPluginPromise ??= (async () => {
    const source = await readFile(resolve(appRoot, "vite.config.ts"), "utf8");
    const start = source.indexOf("const exactHostInitializationPath");
    const end = source.indexOf("\nexport default defineConfig");
    assert.notEqual(start, -1);
    assert.notEqual(end, -1);
    const transformed = await transformWithEsbuild(
      `${source.slice(start, end)}\nglobalThis.__releaseOutputPlugin = releaseOutputPlugin;`,
      resolve(appRoot, "vite.config.ts"),
      { loader: "ts", format: "iife", target: "es2022" },
    );
    const sandbox = {
      TextDecoder,
      TextEncoder,
      Uint8Array,
      basename,
      createHash(algorithm) {
        const hash = nodeCreateHash(algorithm);
        let input;
        return {
          update(value, encoding) {
            input = value;
            hash.update(value, encoding);
            return this;
          },
          digest(encoding) {
            if (encoding === "hex" && input === canonicalHostInitializationSource) {
              return generatedHostInitializationDigest;
            }
            return hash.digest(encoding);
          },
        };
      },
      federationConfig: { name: "cadence_comms_overview" },
      posix,
    };
    sandbox.globalThis = sandbox;
    new Script(transformed.code).runInNewContext(sandbox);
    return sandbox.__releaseOutputPlugin();
  })();
  return releaseOutputPluginPromise;
}

function hostInitializationBundle({ facadeModuleId = exactHostInitializationFacadeId, source = hostInitializationSource } = {}) {
  const size = new TextEncoder().encode(source).byteLength;
  return {
    [hostInitializationPath]: {
      type: "chunk",
      isEntry: false,
      name: "hostInit",
      facadeModuleId,
      code: source,
    },
    "remoteEntry.js": { type: "chunk", isEntry: true, name: "remoteEntry", code: "export {};" },
    "mf-stats.json": {
      type: "asset",
      source: JSON.stringify({
        id: "cadence_comms_overview",
        name: "cadence_comms_overview",
        metaData: {
          name: "cadence_comms_overview",
          remoteEntry: { name: "remoteEntry.js", path: "", type: "module" },
        },
        buildOutput: [
          { fileName: hostInitializationPath, type: "chunk", isEntry: false, size },
          { fileName: "remoteEntry.js", type: "chunk", isEntry: true, size: 10 },
        ],
      }),
    },
  };
}

void test("emits only the federation graph in release mode", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "release");
    const secondOutput = join(root, "second-release");
    const result = await runVite(releaseArguments(output), {
      CADENCE_RELEASE_OUTPUT_DIR: output,
    });

    assert.equal(result.code, 0, result.stderr);
    assert.equal((await lstat(join(output, "index.html")).catch(() => null)) === null, true);
    assert.equal((await lstat(join(output, ".vite")).catch(() => null)) === null, true);
    assert.deepEqual(
      (await outputFiles(output))
        .map((path) => path.slice(output.length + 1))
        .filter((path) => path.startsWith("assets/index-")),
      [],
    );
    for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js"]) {
      assert.notEqual(await lstat(join(output, required)).catch(() => null), null, required);
    }

    const emittedPaths = (await outputFiles(output)).map((path) => path.slice(output.length + 1));
    const stats = JSON.parse(await readFile(join(output, "mf-stats.json"), "utf8"));
    assert.equal(Object.hasOwn(stats, "assetAnalysis"), false);
    const secondResult = await runVite(releaseArguments(secondOutput), {
      CADENCE_RELEASE_OUTPUT_DIR: secondOutput,
    });
    assert.equal(secondResult.code, 0, secondResult.stderr);
    assert.deepEqual(
      emittedPaths,
      (await outputFiles(secondOutput)).map((path) => path.slice(secondOutput.length + 1)),
    );

    const stalePath = join(secondOutput, "assets", "stale-release.js");
    await writeFile(stalePath, "export const stale = true;\n");
    const rebuiltResult = await runVite(releaseArguments(secondOutput), {
      CADENCE_RELEASE_OUTPUT_DIR: secondOutput,
    });
    assert.equal(rebuiltResult.code, 0, rebuiltResult.stderr);
    assert.equal(
      await lstat(stalePath).catch(() => null),
      null,
      "stale output survived the release rebuild",
    );
  });
});

void test("keeps the standalone entry available outside release mode", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "standalone");
    const result = await runVite([
      "build",
      "--config",
      resolve(appRoot, "vite.config.ts"),
      "--mode",
      "development",
      "--outDir",
      output,
    ]);

    assert.equal(result.code, 0, result.stderr);
    assert.notEqual(await lstat(join(output, "index.html")).catch(() => null), null);
  });
});

void test("requires release builds to use the build command and an absolute configured output", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "release");
    const served = await runVite(
      [
        "dev",
        "--config",
        resolve(appRoot, "vite.config.ts"),
        "--mode",
        "release",
      ],
      { CADENCE_RELEASE_OUTPUT_DIR: output },
    );
    assert.notEqual(served.code, 0);
    assert.match(`${served.stdout}\n${served.stderr}`, /requires the Vite build command/);

    const relative = await runVite(releaseArguments(output), {
      CADENCE_RELEASE_OUTPUT_DIR: "relative-release-output",
    });
    assert.notEqual(relative.code, 0);
    assert.match(
      `${relative.stdout}\n${relative.stderr}`,
      /CADENCE_RELEASE_OUTPUT_DIR must be an absolute output directory/,
    );
  });
});

void test("keeps release host-init cleanup exact and provenance-bound", async () => {
  const source = await readFile(resolve(appRoot, "vite.config.ts"), "utf8");
  assert.match(source, /exactHostInitializationPath/);
  assert.match(source, /exactHostInitializationFacadeId/);
  assert.match(source, /generatedHostInitializationSourceDigests/);
  assert.match(source, /canonicalHostInitializationSource/);
  assert.match(source, /structuralHostInitializationLookalikes/);
  assert.match(source, /authoritativeHostInitialization/);
  assert.match(source, /bundleItemReferencesTarget/);
  assert.match(source, /one authoritative host initialization chunk/);
  assert.match(source, /multiple authoritative host initialization chunks/);
  assert.match(source, /conflicting structural host initialization lookalikes/);
  assert.match(source, /one matching stats record/);
  assert.match(source, /record\.size/);
  assert.match(source, /authoritative federation stats provenance/);
  assert.match(source, /exactHostInitializationFacadeIds\.has/);
  assert.match(source, /item\.name !== "hostInit"/);
  assert.match(source, /authoritativeHostInitialization\.length === 0/);
  assert.match(source, /authoritativeHostInitialization\.length > 1/);
  assert.match(source, /structuralHostInitializationLookalikes\.length !== 1/);
  assert.match(source, /generatedHostInitializationSourceDigests\.has/);
  assert.match(source, /replace\(\/vite-preload-helper-/);
  assert.match(source, /_virtual_mf-localSharedImportMap___mfe_internal__/);
  assert.match(source, /replaceAll\(expectedRemoteName/);
  assert.match(source, /delete bundle\[fileName\]/);
  assert.match(source, /output\.fileName !== fileName/);
  assert.doesNotMatch(source, /facadeModuleId === undefined/);
  assert.doesNotMatch(source, /hostAutoInit\|hostInit\|module-federation/);
  assert.doesNotMatch(source, /startsWith\(["']hostInit-/);
  assert.doesNotMatch(source, /basename\(output\.fileName/);
});

void test("covers host-init cleanup adversarial authority cases", async () => {
  const source = await readFile(resolve(appRoot, "vite.config.ts"), "utf8");
  const cases = [
    ["same-shape user chunk", /structuralHostInitializationLookalikes\.length !== 1/],
    ["omitted or forged facade", /exactHostInitializationFacadeIds\.has/],
    ["multiple authoritative candidates", /authoritativeHostInitialization\.length > 1/],
    ["semantic source mutation", /generatedHostInitializationSourceDigests\.has/],
    ["legitimate generated output", /delete bundle\[fileName\][\s\S]*output\.fileName !== fileName/],
  ];

  for (const [caseName, assertion] of cases) {
    assert.match(source, assertion, `${caseName} is not fail-closed in cleanup authority`);
  }
});

void test("rejects a same-shape user-authored host-init chunk", async () => {
  const plugin = await releaseOutputPlugin();
  assert.throws(
    () => plugin.generateBundle({}, hostInitializationBundle({ facadeModuleId: "/src/user.ts" })),
    /one authoritative host initialization chunk/,
  );

  const conflicting = hostInitializationBundle();
  const userPath = "assets/hostInit-ASDFGHJK.js";
  conflicting[userPath] = {
    ...conflicting[hostInitializationPath],
    name: "hostInit-ASDFGHJK",
    facadeModuleId: "/src/user.ts",
  };
  assert.throws(
    () => plugin.generateBundle({}, conflicting),
    /conflicting structural host initialization lookalikes/,
  );
});

void test("rejects omitted or forged host-init facade identity", async () => {
  const plugin = await releaseOutputPlugin();
  const omitted = hostInitializationBundle();
  delete omitted[hostInitializationPath].facadeModuleId;
  assert.throws(
    () => plugin.generateBundle({}, omitted),
    /one authoritative host initialization chunk/,
  );
  assert.throws(
    () =>
      plugin.generateBundle(
        {},
        hostInitializationBundle({ facadeModuleId: "\0virtual:mf:forged-host-init.js" }),
      ),
    /one authoritative host initialization chunk/,
  );
});

void test("rejects multiple authoritative host-init candidates", async () => {
  const plugin = await releaseOutputPlugin();
  const bundle = hostInitializationBundle();
  const secondPath = "assets/hostInit-QPONMLKJ.js";
  bundle[secondPath] = { ...bundle[hostInitializationPath] };
  bundle["mf-stats.json"].source = JSON.stringify({
    ...JSON.parse(bundle["mf-stats.json"].source),
    buildOutput: [
      ...JSON.parse(bundle["mf-stats.json"].source).buildOutput,
      {
        fileName: secondPath,
        type: "chunk",
        isEntry: false,
        size: new TextEncoder().encode(hostInitializationSource).byteLength,
      },
    ],
  });
  assert.throws(
    () => plugin.generateBundle({}, bundle),
    /multiple authoritative host initialization chunks/,
  );
});

void test("rejects semantic mutation of the generated host-init source", async () => {
  const plugin = await releaseOutputPlugin();
  assert.throws(
    () =>
      plugin.generateBundle(
        {},
        hostInitializationBundle({ source: `${hostInitializationSource}globalThis.mutated=true;` }),
      ),
    /one authoritative host initialization chunk/,
  );
});

void test("removes only the exact legitimate generated host-init entry", async () => {
  const plugin = await releaseOutputPlugin();
  const bundle = hostInitializationBundle();
  assert.doesNotThrow(() => plugin.generateBundle({}, bundle));
  assert.equal(Object.hasOwn(bundle, hostInitializationPath), false);
  assert.equal(Object.hasOwn(bundle, "remoteEntry.js"), true);
  const stats = JSON.parse(bundle["mf-stats.json"].source);
  assert.equal(
    stats.buildOutput.some((output) => output.fileName === hostInitializationPath),
    false,
  );
  assert.equal(stats.buildOutput.some((output) => output.fileName === "remoteEntry.js"), true);
});
