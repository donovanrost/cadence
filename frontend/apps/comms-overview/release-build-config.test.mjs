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

function replaceOnce(source, from, replacement) {
  const index = source.indexOf(from);
  assert.notEqual(index, -1, `fixture does not contain ${JSON.stringify(from)}`);
  return `${source.slice(0, index)}${replacement}${source.slice(index + from.length)}`;
}

const exactHostInitializationFacadeId =
  "\0virtual:mf:__mfe_internal__cadence_comms_overview__mf_owner__1__H_A_I__hostAutoInit__H_A_I__.js";
const generatedHostInitializationDigest =
  "e25074ccfca4c766e209adf9e7529680fcca051c844fa5d6d6c1a8e139601068";
const generatedHostInitializationCanonicalSource = Buffer.from(
  "aW1wb3J0e3Rhc2V9ZnJvbSIuL3ZpdGUtcHJlbG9hZC1oZWxwZXItPGhhc2g+LmpzIjt2YXJ0PWBfX21mX21vZHVsZV9jYWNoZV9fYDtnbG9iYWxUaGlzW3Rd\n" +
    "fHw9e3NoYXJlOnt9LHJlbW90ZTp7fX0sZ2xvYmFsVGhpc1t0XS5zaGFyZXx8PXt9LGdsb2JhbFRoaXNbdF0ucmVtb3RlfHw9e307dmFybj1nbG9iYWxUaGlz\n" +
    "W3RdO2ZvcihsZXRlb2ZPYmplY3Qua2V5cyhuLnNoYXJlKSlpZihlLnN0YXJ0c1dpdGgoYGRlZmF1bHQ6YCkpe2xldHQ9ZS5zbGljZSg4KTtuLnNoYXJlW3Rd\n" +
    "PT09dm9pZDAmJihuLnNoYXJlW3RdPW4uc2hhcmVbZV0pfWVsc2VpZighZS5pbmNsdWRlcyhgOmApKXtsZXR0PWBkZWZhdWx0OmArZTtuLnNoYXJlW3RdPT09\n" +
    "dm9pZDAmJihuLnNoYXJlW3RdPW4uc2hhcmVbZV0pfXZhcnI7YXN5bmNmdW5jdGlvbmkoKXtyZXR1cm5yfHw9KGFzeW5jKCk9PntsZXR0PShlLHQsbixyKT0+\n" +
    "e2xldGk9KEFycmF5LmlzQXJyYXkocik/clswXTpyKXx8YGRlZmF1bHRgLGE9dHx8IW4/ZTplK2BAYCtuLG89e2Nhbm9uaWNhbDppK2A6YCthfTtyZXR1cm5p\n" +
    "PT09ImRlZmF1bHQiJiYoby5hbGlhc2VzPVthXSksb30scj0oZSx0KT0+e2xldG49ZVt0LmNhbm9uaWNhbF07aWYobiE9PXZvaWQwKXJldHVybm47bGV0cj10\n" +
    "LmFsaWFzZXN8fFtdO2ZvcihsZXRub2ZyKXtpZighT2JqZWN0LnByb3RvdHlwZS5oYXNPd25Qcm9wZXJ0eS5jYWxsKGUsbikpY29udGludWU7bGV0cj1lW25d\n" +
    "O2lmKHIhPT12b2lkMClyZXR1cm5lW3QuY2Fub25pY2FsXT1yLHJ9fSxpPVN5bWJvbC5mb3IoYG1vZHVsZS1mZWRlcmF0aW9uLnNoYXJlZC1jYWNoZS1saXN0\n" +
    "ZW5lcnNgKSxhPVN5bWJvbC5mb3IoYG1vZHVsZS1mZWRlcmF0aW9uLnNoYXJlZC1jYWNoZS1vd25lcnNgKSxvPWU9PntsZXR0PWVbYV07cmV0dXJudD09PXZv\n" +
    "aWQwJiYodD1PYmplY3QuY3JlYXRlKG51bGwpLE9iamVjdC5kZWZpbmVQcm9wZXJ0eShlLGEse3ZhbHVlOnQsZW51bWVyYWJsZTohMSxjb25maWd1cmFibGU6\n" +
    "ITEsd3JpdGFibGU6ITF9KSksdH0scz0oZSx0KT0+e3Zhcm47cmV0dXJuKG49ZVthXSk9PW51bGw/dm9pZDA6blt0LmNhbm9uaWNhbF19LGM9KGUsdCxuLHIp\n" +
    "PT57dmFycztlW3QuY2Fub25pY2FsXT1uO2xldGM9dC5hbGlhc2VzfHxbXTtmb3IobGV0dG9mYylPYmplY3QuZGVmaW5lUHJvcGVydHkoZSx0LHt2YWx1ZTpu\n" +
    "LGVudW1lcmFibGU6ITAsY29uZmlndXJhYmxlOiEwLHdyaXRhYmxlOiEwfSk7bGV0bD1lW2FdO3I9PT12b2lkMD9sJiZkZWxldGVsW3QuY2Fub25pY2FsXTpv\n" +
    "KGUpW3QuY2Fub25pY2FsXT1yO2xldHU9KHM9ZVtpXSk9PW51bGw/dm9pZDA6c1t0LmNhbm9uaWNhbF07aWYodSlmb3IobGV0ZW9mdSllKG4pO3JldHVybm59\n" +
    "LGw9YXdhaXQoYXdhaXRlKCgpPT5pbXBvcnQoYC4uL3JlbW90ZUVudHJ5LmpzYCksX19WSVRFX1BSRUxPQURfXyxpbXBvcnQubWV0YS51cmwpKS5pbml0KCks\n" +
    "e3VzZWRTaGFyZWQ6dX09YXdhaXRlKGFzeW5jKCk9PntsZXR7dXNlZFNoYXJlZDplfT1hd2FpdGltcG9ydChgLi9fdmlydHVhbF9tZi1sb2NhbFNoYXJlZElt\n" +
    "cG9ydE1hcF9fX21mZV9pbnRlcm5hbF9fPHJlbW90ZT5fX21mX293bmVyX18xLTxoYXNoPi5qc2ApO3JldHVybnt1c2VkU2hhcmVkOmV9fSxfX1ZJVEVfUFJF\n" +
    "TE9BRF9fLGltcG9ydC5tZXRhLnVybCksZD1lPT57bGV0dD1lO2ZvcihsZXRlPTA7ZTw1O2UrKyl7bGV0ZT10PT1udWxsP3ZvaWQwOnQuZGVmYXVsdDtpZigh\n" +
    "ZXx8dHlwZW9mZSE9YG9iamVjdGB8fE9iamVjdC5rZXlzKGUpLmxlbmd0aD09PTApYnJlYWs7bGV0bj1PYmplY3Qua2V5cyh0KS5maWx0ZXIoZT0+ZSE9PSJk\n" +
    "ZWZhdWx0IikubWFwKGU9PnRbZV0pO2lmKG4ubGVuZ3RoPjAmJm4uc29tZShlPT5lIT09dm9pZDApKWJyZWFrO3Q9ZX1yZXR1cm50fTtmb3IobGV0ZW9mW2B2\n" +
    "dWVgXSl7dmFyZjtsZXRpPXVbZV07aWYoIWl8fGkubWF0ZXJpYWxpemU9PT0hMXx8aS50cmVlU2hha2luZyljb250aW51ZTtsZXRhPXQoZSwoZj1pLnNoYXJl\n" +
    "Q29uZmlnKT09bnVsbD92b2lkMDpmLnNpbmdsZXRvbixpLnZlcnNpb24saS5zY29wZSk7KHIobi5zaGFyZSxhKT09PXZvaWQwfHxzKG4uc2hhcmUsYSk9PT12\n" +
    "b2lkMCkmJmF3YWl0bC5sb2FkU2hhcmUoZSx7Y3VzdG9tU2hhcmVJbmZvOntzaGFyZUNvbmZpZzppLnNoYXJlQ29uZmlnfX0pLnRoZW4oYXN5bmNlPT57bGV0\n" +
    "dD10eXBlb2ZlPT1gZnVuY3Rpb25gP2UoKTplLHI9ZChhd2FpdFByb21pc2UucmVzb2x2ZSh0KSk7YyhuLnNoYXJlLGEscixgPHJlbW90ZT5gKX0pfXJldHVy\n" +
    "bmx9KSgpLHJ9cj1pKCk7ZXhwb3J0e3Jhc2hvc3RJbml0UHJvbWlzZSxpYXNpbml0SG9zdH07",
  "base64",
).toString("utf8");
const preloadHelperHash = "B7qeedMF";
const sharedImportHash = "DaZluorV";
const hostInitializationHash = "CVVfVIas";
const hostInitializationPath = `assets/hostInit-${hostInitializationHash}.js`;
const hostInitializationSource = generatedHostInitializationCanonicalSource
  .replace("./vite-preload-helper-<hash>.js", `./vite-preload-helper-${preloadHelperHash}.js`)
  .replace(
    "./_virtual_mf-localSharedImportMap___mfe_internal__<remote>__mf_owner__1-<hash>.js",
    `./_virtual_mf-localSharedImportMap___mfe_internal__cadence_comms_overview__mf_owner__1-${sharedImportHash}.js`,
  );
const canonicalHostInitializationSource = generatedHostInitializationCanonicalSource;

void test("pins the evidence-derived canonical host-init source to its real digest", () => {
  assert.equal(
    nodeCreateHash("sha256").update(canonicalHostInitializationSource, "utf8").digest("hex"),
    generatedHostInitializationDigest,
  );
});

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
      createHash: nodeCreateHash,
      federationConfig: { name: "cadence_comms_overview" },
      posix,
    };
    sandbox.globalThis = sandbox;
    new Script(transformed.code).runInNewContext(sandbox);
    return sandbox.__releaseOutputPlugin();
  })();
  return releaseOutputPluginPromise;
}

function hostInitializationBundle({
  facadeModuleId = exactHostInitializationFacadeId,
  source = hostInitializationSource,
} = {}) {
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
      ["dev", "--config", resolve(appRoot, "vite.config.ts"), "--mode", "release"],
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
  assert.match(source, /item\.facadeModuleId !== exactHostInitializationFacadeId/);
  assert.match(source, /item\.name !== "hostInit"/);
  assert.match(source, /authoritativeHostInitialization\.length === 0/);
  assert.match(source, /authoritativeHostInitialization\.length > 1/);
  assert.match(source, /structuralHostInitializationLookalikes\.length !== 1/);
  assert.match(source, /generatedHostInitializationSourceDigests\.has/);
  assert.match(source, /preloadImport/);
  assert.match(source, /sharedImport/);
  assert.match(source, /generatedImportLiterals/);
  assert.match(source, /_virtual_mf-localSharedImportMap___mfe_internal__/);
  assert.doesNotMatch(source, /replaceAll\(expectedRemoteName/);
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
    ["omitted or forged facade", /item\.facadeModuleId !== exactHostInitializationFacadeId/],
    ["multiple authoritative candidates", /authoritativeHostInitialization\.length > 1/],
    ["semantic source mutation", /generatedHostInitializationSourceDigests\.has/],
    [
      "legitimate generated output",
      /delete bundle\[fileName\][\s\S]*output\.fileName !== fileName/,
    ],
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
  assert.throws(
    () =>
      plugin.generateBundle(
        {},
        hostInitializationBundle({ facadeModuleId: exactHostInitializationFacadeId.slice(1) }),
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

void test("rejects semantic whitespace mutations in string and template literals", async () => {
  const plugin = await releaseOutputPlugin();
  const stringLiteral = '"default"';
  const mutations = [
    [
      "template literal",
      replaceOnce(hostInitializationSource, "`__mf_module_cache__`", "`__mf_module_cache__ `"),
    ],
    [
      "string literal",
      replaceOnce(hostInitializationSource, stringLiteral, String.raw`\" default\"`),
    ],
  ];
  for (const [mutation, source] of mutations) {
    const bundle = hostInitializationBundle({ source });
    assert.throws(
      () => plugin.generateBundle({}, bundle),
      /one authoritative host initialization chunk/,
      mutation,
    );
    assert.equal(Object.hasOwn(bundle, hostInitializationPath), true, `${mutation} was removed`);
  }
});

void test("rejects a remote-name substitution in a non-import template literal", async () => {
  const plugin = await releaseOutputPlugin();
  const bundle = hostInitializationBundle({
    source: replaceOnce(hostInitializationSource, "`<remote>`", "`cadence_comms_overview`"),
  });
  assert.throws(
    () => plugin.generateBundle({}, bundle),
    /one authoritative host initialization chunk/,
  );
  assert.equal(Object.hasOwn(bundle, hostInitializationPath), true);
});

void test("removes only the exact legitimate generated host-init entry", async () => {
  const plugin = await releaseOutputPlugin();
  assert.equal(plugin.name, "cadence-comms-overview-release-output");
  assert.equal(typeof plugin.generateBundle, "function");
  const bundle = hostInitializationBundle();
  assert.doesNotThrow(() => plugin.generateBundle({}, bundle));
  assert.equal(Object.hasOwn(bundle, hostInitializationPath), false);
  assert.equal(Object.hasOwn(bundle, "remoteEntry.js"), true);
  const stats = JSON.parse(bundle["mf-stats.json"].source);
  assert.equal(stats.buildOutput.length, 1);
  assert.equal(
    stats.buildOutput.some((output) => output.fileName === hostInitializationPath),
    false,
  );
  assert.equal(
    stats.buildOutput.some((output) => output.fileName === "remoteEntry.js"),
    true,
  );
});
