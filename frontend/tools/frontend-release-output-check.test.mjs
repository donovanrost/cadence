import { jsonFixture, fixtureRecord } from "../test-support/json-fixture.ts";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import {
  assertLocalReference,
  assertImportReferences,
  assertOutputOutsideRepository,
  assertReleaseArtifactPath,
  canonicalPathWithMissingTail,
  parseRemoteNameArgument,
  parseOutputDirectoryArgument,
  pathsOverlap,
  validateReleaseOutput,
} from "./frontend-release-output-check.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const checkerPath = resolve(import.meta.dirname, "frontend-release-output-check.mjs");
const execFileAsync = promisify(execFile);
const legitimateHostInitializationSource =
  'import{t as e}from"./vite-preload-helper-C2lBtS7w.js";var t=`__mf_module_cache__`;globalThis[t]||={share:{},remote:{}},globalThis[t].share||={},globalThis[t].remote||={};var n=globalThis[t];for(let e of Object.keys(n.share))if(e.startsWith(`default:`)){let t=e.slice(8);n.share[t]===void 0&&(n.share[t]=n.share[e])}else if(!e.includes(`:`)){let t=`default:`+e;n.share[t]===void 0&&(n.share[t]=n.share[e])}var r;async function i(){return r||=(async()=>{let t=(e,t,n,r)=>{let i=(Array.isArray(r)?r[0]:r)||`default`,a=t||!n?e:e+`@`+n,o={canonical:i+`:`+a};return i==="default"&&(o.aliases=[a]),o},r=(e,t)=>{let n=e[t.canonical];if(n!==void 0)return n;let r=t.aliases||[];for(let n of r){if(!Object.prototype.hasOwnProperty.call(e,n))continue;let r=e[n];if(r!==void 0)return e[t.canonical]=r,r}},i=Symbol.for(`module-federation.shared-cache-listeners`),a=Symbol.for(`module-federation.shared-cache-owners`),o=e=>{let t=e[a];return t===void 0&&(t=Object.create(null),Object.defineProperty(e,a,{value:t,enumerable:!1,configurable:!1,writable:!1})),t},s=(e,t)=>{var n;return(n=e[a])==null?void 0:n[t.canonical]},c=(e,t,n,r)=>{var s;e[t.canonical]=n;let c=t.aliases||[];for(let t of c)Object.defineProperty(e,t,{value:n,enumerable:!0,configurable:!0,writable:!0});let l=e[a];r===void 0?l&&delete l[t.canonical]:o(e)[t.canonical]=r;let u=(s=e[i])==null?void 0:s[t.canonical];if(u)for(let e of u)e(n);return n},l=await(await e(()=>import(`../remoteEntry.js`),[])).init(),{usedShared:u}=await e(async()=>{let{usedShared:e}=await import(`./_virtual_mf-localSharedImportMap___mfe_internal__cadence_comms_overview__mf_owner__1-CKx0RqLR.js`);return{usedShared:e}},[]),d=e=>{let t=e;for(let e=0;e<5;e++){let e=t==null?void 0:t.default;if(!e||typeof e!=`object`||Object.keys(e).length===0)break;let n=Object.keys(t).filter(e=>e!=="default").map(e=>t[e]);if(n.length>0&&n.some(e=>e!==void 0))break;t=e}return t};for(let e of[`vue`]){var f;let i=u[e];if(!i||i.materialize===!1||i.treeShaking)continue;let a=t(e,(f=i.shareConfig)==null?void 0:f.singleton,i.version,i.scope);(r(n.share,a)===void 0||s(n.share,a)===void 0)&&await l.loadShare(e,{customShareInfo:{shareConfig:i.shareConfig}}).then(async e=>{let t=typeof e==`function`?e():e,r=d(await Promise.resolve(t));c(n.share,a,r,`cadence_comms_overview`)})}return l})(),r}r=i();export{r as hostInitPromise,i as initHost};';
const releaseHostInitializationSource = legitimateHostInitializationSource
  .replaceAll("cadence_comms_overview", "cadence_telemetry_decom")
  .replaceAll("C2lBtS7w", "B7qeedMF")
  .replaceAll("CKx0RqLR", "Dhd1hqIP")
  .replace("import(`../remoteEntry.js`),[]", "import(`../remoteEntry.js`),[],import.meta.url")
  .replace("}},[]),d=e=>", "}},[],import.meta.url),d=e=>");

async function makeFixture(baseDirectory = tmpdir()) {
  const root = await mkdtemp(join(baseDirectory, "cadence-frontend-release-check-"));
  const assets = join(root, "assets");
  await mkdir(assets, { recursive: true });

  const files = {
    "remoteEntry.js": `
      import "./assets/quoted.js";
      import \`./assets/backtick.js\`;
      import "./assets/side-effect.js";
      export { value } from "./assets/exported.js";
      const loaded = import("./assets/dynamic.js");
      const icon = new URL("./assets/image.svg", import.meta.url);
      import "https://cdn.example.test/remote.js";
      import "//cdn.example.test/remote.js";
      const text = "import('./missing-string.js')";
      // import("./missing-line-comment.js")
      /* import("./missing-block-comment.js") */
      const member = object.import("./missing-member-call.js");
      void loaded; void icon; void member;
    `,
    "assets/quoted.js": "export const quoted = true;\n",
    "assets/backtick.js": "export const backtick = true;\n",
    "assets/side-effect.js": "globalThis.sideEffect = true;\n",
    "assets/exported.js": "export const value = true;\n",
    "assets/dynamic.js": "export const dynamic = true;\n",
    "assets/image.svg": '<svg xmlns="http://www.w3.org/2000/svg"/>\n',
    "assets/font.woff2": "font fixture\n",
    "assets/imported.css": ".imported { color: red; }\n",
    "assets/imported-quoted.css": ".quoted { color: blue; }\n",
    "assets/style.css": `
      /* url(./missing-comment.png) @import "./missing-comment.css"; */
      :root { --copy: "url(./missing-string.png)"; }
      @import url("./imported.css");
      @import "./imported-quoted.css";
      .icon { background: URL(./image.svg); src: url(./font.woff2); }
      .external { background: url(https://cdn.example.test/image.svg); }
      .protocol-relative { background: url(//cdn.example.test/image.svg); }
    `,
    "mf-manifest.json": JSON.stringify({
      id: "fixture_remote",
      name: "fixture_remote",
      metaData: { publicPath: "auto", remoteEntry: { path: "", name: "remoteEntry.js" } },
      shared: [
        {
          name: "vue",
          assets: { js: { async: [], sync: ["remoteEntry.js"] }, css: { async: [], sync: [] } },
        },
      ],
      exposes: [
        {
          name: "./App",
          assets: {
            js: {
              async: [
                "assets/quoted.js",
                "assets/backtick.js",
                "assets/side-effect.js",
                "assets/exported.js",
                "assets/dynamic.js",
              ],
              sync: ["remoteEntry.js"],
            },
            css: { async: [], sync: ["assets/style.css"] },
          },
        },
      ],
    }),
    "mf-stats.json": JSON.stringify({
      buildOutput: [
        { fileName: "remoteEntry.js" },
        { fileName: "assets/quoted.js" },
        { fileName: "assets/backtick.js" },
        { fileName: "assets/side-effect.js" },
        { fileName: "assets/exported.js" },
        { fileName: "assets/dynamic.js" },
        { fileName: "assets/image.svg" },
        { fileName: "assets/imported.css" },
        { fileName: "assets/imported-quoted.css" },
        { fileName: "assets/style.css" },
        { fileName: "assets/font.woff2" },
      ],
    }),
  };

  for (const [path, contents] of Object.entries(files)) {
    const target = join(root, path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, contents);
  }

  return root;
}

/** @param {string} root @param {string} id @param {string} [name] */
async function setManifestIdentity(root, id, name = id) {
  const manifestPath = join(root, "mf-manifest.json");
  const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
  manifest.id = id;
  manifest.name = name;
  await writeFile(manifestPath, JSON.stringify(manifest));
}

/** @template T @param {(root:string)=>Promise<T>} callback @param {string} [baseDirectory] @returns {Promise<T>} */
async function withFixture(callback, baseDirectory = tmpdir()) {
  const root = await makeFixture(baseDirectory);
  try {
    return await callback(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

/** @param {string} root @param {string} expectedRemoteName @param {RegExp} pattern @param {import("./frontend-release-output-check.mjs").OutputOptions} [options] */
async function expectCheckFailure(root, expectedRemoteName, pattern, options = {}) {
  await assert.rejects(
    () => validateReleaseOutput(root, expectedRemoteName, repositoryRoot, options),
    pattern,
  );
}

/** @param {string} root @param {string} remoteName @param {string} source @param {{helperHash?:string,sharedImportHash?:string}} [options] */
async function addHostInitializationFixture(
  root,
  remoteName,
  source,
  { helperHash = "C2lBtS7w", sharedImportHash = "CKx0RqLR" } = {},
) {
  const hostPath = "assets/hostInit-ABCDEFGH.js";
  const helperPath = `assets/vite-preload-helper-${helperHash}.js`;
  const sharedImportMapPath = `assets/_virtual_mf-localSharedImportMap___mfe_internal__${remoteName}__mf_owner__1-${sharedImportHash}.js`;
  await writeFile(join(root, hostPath), source);
  await writeFile(join(root, helperPath), "export const preload = true;\n");
  await writeFile(join(root, sharedImportMapPath), "export const usedShared = {};\n");

  const manifestPath = join(root, "mf-manifest.json");
  const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
  manifest.id = remoteName;
  manifest.name = remoteName;
  assetImports(manifest).push(helperPath, sharedImportMapPath);
  await writeFile(manifestPath, JSON.stringify(manifest));

  const statsPath = join(root, "mf-stats.json");
  const stats = jsonFixture(await readFile(statsPath, "utf8"));
  stats.id = remoteName;
  stats.name = remoteName;
  stats.metaData = {
    name: remoteName,
    remoteEntry: { name: "remoteEntry.js", path: "", type: "module" },
  };
  outputRows(stats).push(
    {
      fileName: hostPath,
      type: "chunk",
      isEntry: false,
      size: Buffer.byteLength(source),
    },
    { fileName: helperPath },
    { fileName: sharedImportMapPath },
  );
  await writeFile(statsPath, JSON.stringify(stats));
}

void test("accepts the complete release reference closure, including comments and external URLs", async () => {
  await withFixture(async (root) => {
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("accepts the explicit Comms Module Federation identity", async () => {
  await withFixture(async (root) => {
    await setManifestIdentity(root, "cadence_comms_overview");
    const result = await validateReleaseOutput(root, "cadence_comms_overview", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("accepts Telemetry after mutating only the fixture manifest identity", async () => {
  await withFixture(async (root) => {
    await setManifestIdentity(root, "cadence_telemetry_decom");
    const result = await validateReleaseOutput(root, "cadence_telemetry_decom", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("requires both generated manifest identity fields to match the expected remote", async () => {
  await withFixture(async (root) => {
    await setManifestIdentity(root, "cadence_comms_overview", "cadence_telemetry_decom");
    await expectCheckFailure(root, "cadence_comms_overview", /manifest identity/);
  });

  await withFixture(async (root) => {
    await setManifestIdentity(root, "cadence_telemetry_decom", "cadence_comms_overview");
    await expectCheckFailure(root, "cadence_telemetry_decom", /manifest identity/);
  });
});

void test("resolves the actual Cadence repository root from the shared tools path", async () => {
  await withFixture(async (root) => {
    const result = await validateReleaseOutput(root, "fixture_remote");
    assert.equal(result.fileCount > 0, true);
  }, dirname(repositoryRoot));
});

void test("scans quoted and unquoted JavaScript and CSS references", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "remoteEntry.js"), 'import "../outside.js";\n');
    await expectCheckFailure(root, "fixture_remote", /escapes the output|traversal/);
  });

  await withFixture(async (root) => {
    assert.doesNotThrow(() => parseOutputDirectoryArgument(["--outDir", root]));
    await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
  });
});

void test("fails closed for unresolved dynamic local imports and asset URLs", async () => {
  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      'const directory = "../";\nimport(directory + "outside.js");\n',
    );
    await expectCheckFailure(root, "fixture_remote", /unresolved dynamic local import/);
  });

  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      'const name = "image";\nnew URL(`./assets/${name}.svg`, import.meta.url);\n',
    );
    await expectCheckFailure(
      root,
      "fixture_remote",
      /unresolved dynamic local asset URL|dynamic template/,
    );
  });

  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      'const target = "./assets/dynamic.js";\nnew URL("../" + target, import.meta.url);\n',
    );
    await expectCheckFailure(root, "fixture_remote", /unresolved dynamic local asset URL/);
  });

  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      "const currentPage = new URL(window.location.href);\nvoid currentPage;\n",
    );
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      "const currentPage = new URL(target.value, window.location.origin);\nvoid currentPage;\n",
    );
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  for (const source of [
    'const target = "./assets/dynamic.js";\nnew Worker(target);\n',
    'const target = "dynamic";\nnew SharedWorker("./assets/" + target);\n',
    'const target = "dynamic";\nnavigator.serviceWorker.register(`./assets/${target}.js`);\n',
    'const target = "./assets/dynamic.js";\nnew globalThis["Worker"](target);\n',
    'const target = "dynamic";\nnew globalThis.URL("./assets/" + target, import.meta.url);\n',
    'const target = "dynamic";\nnavigator["serviceWorker"]["register"](`./assets/${target}.js`);\n',
  ]) {
    await withFixture(async (root) => {
      await writeFile(join(root, "remoteEntry.js"), source);
      await expectCheckFailure(
        root,
        "fixture_remote",
        /unresolved dynamic worker URL|unresolved dynamic local asset URL|dynamic template/,
      );
    });
  }
});

void test("does not confuse division followed by a regex literal containing import text", async () => {
  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      'if (true) /import\\("outside.js"\\)/.test("import");\nconst matches = 4 / /import\\("outside.js"\\)/.test("import");\nvoid matches;\n',
    );
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("nested templates preserve string boundaries and later real import checks", () => {
  const prefix =
    "const label = `Review ${active ? `group ${group.join(`, `)}` : `\\`${run}\\``}`; const fields = [{label:`active from`,key:`active_from_text`}];";
  const files = new Set(["assets/feature.js", "assets/valid.js"]);
  const references = new Set();
  assertImportReferences(
    prefix + 'import "./valid.js";',
    "assets/feature.js",
    files,
    repositoryRoot,
    references,
  );
  assert.deepEqual([...references], ["assets/valid.js"]);
  assert.throws(
    () =>
      assertImportReferences(
        prefix + 'import "./missing.js";',
        "assets/feature.js",
        files,
        repositoryRoot,
      ),
    /points to missing/,
  );
});

void test("nested template expressions cannot hide unresolved imports", () => {
  const files = new Set(["assets/feature.js"]);
  for (const source of [
    "const label = `outer ${`inner ${import(target)}`}`;",
    "const label = `outer ${ {value: `inner ${import(target)}`} }`;",
    "const label = `outer ${`unfinished`;",
  ]) {
    assert.throws(
      () => assertImportReferences(source, "assets/feature.js", files, repositoryRoot),
      /dynamic template|unterminated/,
    );
  }
});

void test("accepts statically bounded worker references", async () => {
  await withFixture(async (root) => {
    await writeFile(
      join(root, "remoteEntry.js"),
      'new Worker("./assets/dynamic.js");\nnew globalThis.Worker("./assets/dynamic.js");\nnew SharedWorker(new URL("./assets/dynamic.js", import.meta.url));\nnew globalThis.URL("./assets/dynamic.js", import.meta.url);\nnavigator.serviceWorker.register("./assets/dynamic.js");\nnavigator["serviceWorker"]["register"]("./assets/dynamic.js");\n',
    );
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("only an explicitly authoritative host publication may contain runtime URLs", () => {
  const files = new Set(["host.js"]);
  const options = { authoritativeHostPublication: true };
  /** @param {string} source */
  const assertAuthoritativeHostSource = (source) =>
    assert.doesNotThrow(() =>
      assertImportReferences(source, "host.js", files, repositoryRoot, new Set(), options),
    );

  assertAuthoritativeHostSource("function mutable(value) { return new URL(value); }\n");

  assert.throws(
    () =>
      assertImportReferences(
        "function mutable(value) { return new URL(value); }\n",
        "host.js",
        files,
        repositoryRoot,
        new Set(),
      ),
    /unresolved dynamic local asset URL/,
  );
  assert.throws(
    () =>
      assertImportReferences(
        "function lf(e, t) { let n = t; return new URL(`__module_federation_remote__${cf(e)}`, n); }\n",
        "host.js",
        files,
        repositoryRoot,
        new Set(),
      ),
    /unresolved dynamic local asset URL/,
  );
});

void test("accepts generated federation navigation URLs based on browser location", () => {
  const files = new Set(["federated-application.js"]);
  assert.doesNotThrow(() =>
    assertImportReferences(
      "function navigate(value) { return new URL(value, globalThis.location.href); }\n",
      "federated-application.js",
      files,
      repositoryRoot,
      new Set(),
      { generatedModuleFederation: true },
    ),
  );
  assert.doesNotThrow(() =>
    assertImportReferences(
      "function current() { return new URL(globalThis.location.href); }\n",
      "federated-application.js",
      files,
      repositoryRoot,
      new Set(),
      { generatedModuleFederation: true },
    ),
  );
  assert.throws(
    () =>
      assertImportReferences(
        "function navigate(value) { let base = globalThis.location; base = {}; return new URL(value, base.href); }\n",
        "federated-application.js",
        files,
        repositoryRoot,
        new Set(),
        { generatedModuleFederation: true },
      ),
    /unresolved dynamic local asset URL/,
  );
  assert.throws(
    () =>
      assertImportReferences(
        "function load(value) { return new URL(value); }\n",
        "federated-application.js",
        files,
        repositoryRoot,
        new Set(),
        { generatedModuleFederation: true },
      ),
    /unresolved dynamic local asset URL/,
  );
});

void test("rejects encoded, split, invalid, and cross-platform forbidden artifact paths", () => {
  for (const path of [
    "assets/contract%2Dprobe.js",
    "assets/contract%2eprobe.js",
    "assets/contract/probe.js",
    "assets/contract\\probe.js",
    "assets/invalid%ZZ.js",
    "assets/contract%2Fprobe.js",
  ]) {
    assert.throws(() => assertReleaseArtifactPath(path), /forbidden|percent|separator/);
  }

  assert.doesNotThrow(() => assertReleaseArtifactPath("assets/Contest.js"));
  assert.doesNotThrow(() => assertReleaseArtifactPath("assets/Latest.js"));
});

void test("rejects local-reference normalization collisions and Windows or POSIX escapes", () => {
  const files = new Set(["remoteEntry.js", "assets/Latest.js"]);
  const outputRoot = "/tmp/cadence-release-reference-fixture";
  assert.doesNotThrow(() =>
    assertLocalReference(
      "./assets/Latest.js",
      "remoteEntry.js",
      files,
      "fixture import",
      outputRoot,
    ),
  );

  for (const reference of [
    "assets/../remoteEntry.js",
    "assets//Latest.js",
    "assets\\Latest.js",
    "assets/%2e%2e/remoteEntry.js",
    "C:/checkout/secret.js",
    "C:\\checkout\\secret.js",
    "/checkout/secret.js",
    "assets/%ZZ.js",
  ]) {
    assert.throws(
      () => assertLocalReference(reference, "remoteEntry.js", files, "fixture import", outputRoot),
      /absolute|traversal|empty|separator|percent|missing|normalization/,
    );
  }
});

void test("rejects a real CSS reference that is absent and any standalone HTML", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "assets/style.css"), '.real { background: url("./missing.png"); }');
    await expectCheckFailure(root, "fixture_remote", /CSS URL points to missing/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "index.html"), "<img src=assets/missing.svg>");
    await expectCheckFailure(root, "fixture_remote", /standalone HTML artifact/);
  });
});

void test("requires federation manifest and stats references to existing files", async () => {
  await withFixture(async (root) => {
    const manifestPath = join(root, "mf-manifest.json");
    const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
    fixtureRecord(fixtureRecord(firstExpose(manifest).assets).js).async = ["assets/missing.js"];
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, "fixture_remote", /points to missing/);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    outputRows(stats).push({ fileName: "assets/missing.js" });
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /points to missing/);
  });
});

void test("distinguishes producer size metadata from explicit byte metadata", async () => {
  await withFixture(async (root) => {
    const manifestPath = join(root, "mf-manifest.json");
    const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
    fixtureRecord(fixtureRecord(manifest.metaData).remoteEntry).size = 2381;
    await writeFile(manifestPath, JSON.stringify(manifest));
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    fixtureRecord(outputRows(stats)[0]).size = 2381;
    await writeFile(statsPath, JSON.stringify(stats));
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    fixtureRecord(outputRows(stats)[0]).byteLength = 2381;
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /byte length/);
  });
});

void test("rejects stats-only artifacts and recursively nested absolute or invalid paths", async () => {
  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    outputRows(stats).push({ fileName: "assets/stats-only.js" });
    await writeFile(join(root, "assets", "stats-only.js"), "export const statsOnly = true;\n");
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /missing from manifest closure/);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    stats.nested = { metadata: { path: join(repositoryRoot, "checkout-secret.js") } };
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /nested\.metadata\.path.*absolute local path/);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    stats.nested = { metadata: { fileName: "assets/invalid%ZZ.js" } };
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /invalid percent encoding/);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    const hostInitPath = "assets/hostInit-ABCDEFGH.js";
    const hostInitSource = "globalThis.hostInitPromise = true; export const initHost = true;\n";
    await writeFile(join(root, hostInitPath), hostInitSource);
    stats.id = "fixture_remote";
    stats.name = "fixture_remote";
    stats.metaData = {
      name: "fixture_remote",
      remoteEntry: { name: "remoteEntry.js", path: "", type: "module" },
    };
    outputRows(stats).push({
      fileName: hostInitPath,
      type: "chunk",
      isEntry: false,
      size: Buffer.byteLength(hostInitSource),
    });
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /missing from manifest closure/);
  });
});

void test("rejects extra empty or nested output directories", async () => {
  await withFixture(async (root) => {
    await mkdir(join(root, "empty-directory"));
    await expectCheckFailure(root, "fixture_remote", /unexpected or nested directory/);
  });

  await withFixture(async (root) => {
    await mkdir(join(root, "assets", "nested"));
    await writeFile(join(root, "assets", "nested", "asset.js"), "export const nested = true;\n");
    await expectCheckFailure(root, "fixture_remote", /unexpected or nested directory/);
  });
});

void test("rejects near-miss generated host-init structural spoofs", async () => {
  const hostInitPath = "assets/hostInit-ABCDEFGH.js";
  const sources = [
    'import{t as e}from"./vite-preload-helper-ABCDEFGH.js";var t=`__mf_module_cache__`;globalThis[t]||={share:{},remote:{}};globalThis.attacker=true;export{t as hostInitPromise,t as initHost};\n',
    "/* FEDERATION_ALLOW_NEW_FUNCTION */ globalThis.hostInitPromise=true;export const initHost=true;\n",
    'import{t as e}from"./vite-preload-helper-ABCDEFGH.js";var t=`__mf_module_cache__`;globalThis[t]||={share:{},remote:{}};export{t as hostInitPromise};\n',
  ];

  for (const source of sources) {
    await withFixture(async (root) => {
      const statsPath = join(root, "mf-stats.json");
      const stats = jsonFixture(await readFile(statsPath, "utf8"));
      await writeFile(join(root, hostInitPath), source);
      stats.id = "fixture_remote";
      stats.name = "fixture_remote";
      stats.metaData = {
        name: "fixture_remote",
        remoteEntry: { name: "remoteEntry.js", path: "", type: "module" },
      };
      outputRows(stats).push({
        fileName: hostInitPath,
        type: "chunk",
        isEntry: false,
        size: Buffer.byteLength(source),
      });
      await writeFile(statsPath, JSON.stringify(stats));
      await expectCheckFailure(root, "fixture_remote", /missing from manifest closure/);
    });
  }
});

void test("binds generated host-init semantics while allowing filename hash variance", async () => {
  await withFixture(async (root) => {
    const remoteName = "cadence_comms_overview";
    await addHostInitializationFixture(root, remoteName, legitimateHostInitializationSource);
    const result = await validateReleaseOutput(root, remoteName, repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  await withFixture(async (root) => {
    const remoteName = "cadence_comms_overview";
    const filenameHashVariant = legitimateHostInitializationSource
      .replaceAll("C2lBtS7w", "A1b2C3d4")
      .replaceAll("CKx0RqLR", "D4e5F6g7");
    await addHostInitializationFixture(root, remoteName, filenameHashVariant, {
      helperHash: "A1b2C3d4",
      sharedImportHash: "D4e5F6g7",
    });
    const result = await validateReleaseOutput(root, remoteName, repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  await withFixture(async (root) => {
    const remoteName = "fixture_remote";
    const alteredSource = legitimateHostInitializationSource.replaceAll(
      "cadence_comms_overview",
      remoteName,
    );
    await addHostInitializationFixture(root, remoteName, alteredSource);
    await expectCheckFailure(root, remoteName, /stats references.*missing from manifest closure/);
  });
});

void test("accepts the exact release-mode generated host-init facade", async () => {
  await withFixture(async (root) => {
    const remoteName = "cadence_telemetry_decom";
    await addHostInitializationFixture(root, remoteName, releaseHostInitializationSource, {
      helperHash: "B7qeedMF",
      sharedImportHash: "Dhd1hqIP",
    });
    const result = await validateReleaseOutput(root, remoteName, repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("canonicalizes deployment paths and rejects cross-publication escapes", async () => {
  for (const deploymentPath of [
    "comms-overview/../telemetry-decom/remoteEntry.js",
    "comms-overview\\..\\telemetry-decom\\remoteEntry.js",
    "comms-overview/%2e%2e/telemetry-decom/remoteEntry.js",
    "comms-overview//remoteEntry.js",
  ]) {
    await withFixture(async (root) => {
      await writeFile(
        join(root, "assets", "quoted.js"),
        `const publication = "/assets/application-host/${deploymentPath}";\n`,
      );
      await expectCheckFailure(
        root,
        "fixture_remote",
        /deployment path|unexpected deployment path|percent/,
        { allowedDeploymentPath: "comms-overview" },
      );
    });
  }

  for (const publication of [
    `const publication = "/assets\\/application-host\\/comms-overview\\x2FremoteEntry.js";\n`,
    `const publication = "\\x2Fassets\\x2Fapplication-host\\x2Fcomms-overview\\x2FremoteEntry.js";\n`,
    `const publication = "\\u002Fassets\\u002Fapplication-host\\u002Fcomms-overview\\u002FremoteEntry.js";\n`,
    `const publication = "\\u{2F}assets\\u{002F}application-host\\u{0002F}comms-overview\\u{00002F}remoteEntry.js";\n`,
  ]) {
    await withFixture(async (root) => {
      await writeFile(join(root, "assets", "quoted.js"), publication);
      const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot, {
        allowedDeploymentPath: "comms-overview",
      });
      assert.equal(result.fileCount > 0, true);
    });
  }

  await withFixture(async (root) => {
    await writeFile(
      join(root, "assets", "quoted.js"),
      `const publication = "\\x2Fassets\\/application-host\\u002Ftelemetry-decom\\u{2F}remoteEntry.js";\n`,
    );
    await expectCheckFailure(root, "fixture_remote", /unexpected deployment path|deployment path/, {
      allowedDeploymentPath: "comms-overview",
    });
  });
});

void test("requires generated dynamic-import exceptions to have stats provenance and graph authority", async () => {
  const attackerShape =
    "const FEDERATION_ALLOW_NEW_FUNCTION = true;\nconst loaded = ready ? fallback : import(target).then(done).catch(fail);\nvoid loaded;\n";
  await withFixture(async (root) => {
    await writeFile(join(root, "remoteEntry.js"), attackerShape);
    await expectCheckFailure(root, "fixture_remote", /unresolved dynamic local import/);
  });

  await withFixture(async (root) => {
    const generatedPath = "assets/dist-ABCDEFGH.js";
    const generatedSource =
      "const loaded = ready ? fallback : import(target).then(done).catch(fail);\nvoid loaded;\n";
    await writeFile(join(root, generatedPath), generatedSource);
    const manifestPath = join(root, "mf-manifest.json");
    const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
    assetImports(manifest).push(generatedPath);
    await writeFile(manifestPath, JSON.stringify(manifest));
    const statsPath = join(root, "mf-stats.json");
    const stats = jsonFixture(await readFile(statsPath, "utf8"));
    stats.id = "fixture_remote";
    stats.name = "fixture_remote";
    stats.metaData = {
      name: "fixture_remote",
      remoteEntry: { name: "remoteEntry.js", path: "", type: "module" },
    };
    outputRows(stats).push({
      fileName: generatedPath,
      type: "chunk",
      isEntry: false,
      size: Buffer.byteLength(generatedSource),
    });
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /unresolved dynamic local import/);
  });
});

void test("rejects forbidden names, renamed forbidden chunks, source maps, and stale output", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "main-renamed.js"), "export const stale = true;\n");
    await expectCheckFailure(root, "fixture_remote", /standalone, test, or contract artifact/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "failure-application.js"), "export const stale = true;\n");
    await expectCheckFailure(root, "fixture_remote", /standalone, test, or contract artifact/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "quoted.js"), 'const service = "demo-auth-service";\n');
    await expectCheckFailure(root, "fixture_remote", /forbidden demo-auth service/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "stale.js"), "export const stale = true;\n");
    await expectCheckFailure(root, "fixture_remote", /unreferenced or stale artifact/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "quoted.js.map"), "{}\n");
    await expectCheckFailure(root, "fixture_remote", /source-map artifact/);
  });
});

void test("rejects forbidden publication references in admitted file contents", async () => {
  /** @type {[string, RegExp][]} */
  const forbiddenReferences = [
    ['const probe = "contract-probe";\n', /forbidden contract probe/],
    ['const origin = "http://localhost:4174";\n', /forbidden development URL/],
    ['const origin = "http://127.0.0.1:4174";\n', /forbidden development URL/],
    ["if (import.meta.hot) import.meta.hot.accept();\n", /forbidden Vite client or HMR reference/],
    ["//# sourceMappingURL=quoted.js.map\n", /forbidden source-map reference/],
    ['const fallbackUrl = "/fallback";\n', /forbidden mutable fallback URL/],
    ['const entry = "phoenix-bootstrap";\n', /forbidden standalone bootstrap reference/],
  ];

  for (const [contents, message] of forbiddenReferences) {
    await withFixture(async (root) => {
      await writeFile(join(root, "assets", "quoted.js"), contents);
      await expectCheckFailure(root, "fixture_remote", message);
    });
  }

  await withFixture(async (root) => {
    await writeFile(join(root, "assets", "quoted.js"), 'const className = "ops-standalone";\n');
    const result = await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });

  await withFixture(async (root) => {
    const manifestPath = join(root, "mf-manifest.json");
    const manifest = jsonFixture(await readFile(manifestPath, "utf8"));
    firstExpose(manifest).path = "./Failure";
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, "fixture_remote", /non-publication module/);
  });
});

void test("rejects output-root and nested symlinks", async () => {
  await withFixture(async (root) => {
    const linkRoot = await mkdtemp(join(tmpdir(), "cadence-frontend-release-output-link-"));
    const link = join(linkRoot, "release");
    try {
      await symlink(root, link, "dir");
      await assert.rejects(
        () => validateReleaseOutput(link, "fixture_remote", repositoryRoot),
        /output directory must not be a symlink/,
      );
    } finally {
      await rm(linkRoot, { recursive: true, force: true });
    }

    await symlink(join(root, "assets", "quoted.js"), join(root, "assets", "linked.js"));
    await expectCheckFailure(root, "fixture_remote", /unsupported output entry/);
  });
});

void test("rejects repository overlap in both directions after canonicalizing symlinks and missing tails", async () => {
  assert.equal(pathsOverlap(repositoryRoot, repositoryRoot), true);
  assert.equal(pathsOverlap(repositoryRoot, dirname(repositoryRoot)), true);
  assert.equal(pathsOverlap(repositoryRoot, join(repositoryRoot, "missing-release-tail")), true);

  assert.throws(
    () => assertOutputOutsideRepository(repositoryRoot, repositoryRoot),
    /outside the repository/,
  );
  assert.throws(
    () => assertOutputOutsideRepository(dirname(repositoryRoot), repositoryRoot),
    /outside the repository/,
  );

  const linkRoot = await mkdtemp(join(tmpdir(), "cadence-frontend-release-link-"));
  const link = join(linkRoot, "repository-link");
  try {
    await symlink(repositoryRoot, link, "dir");
    const missingTail = join(link, "missing-release-tail");
    assert.equal(
      canonicalPathWithMissingTail(missingTail),
      join(repositoryRoot, "missing-release-tail"),
    );
    assert.throws(
      () =>
        assertOutputOutsideRepository(
          canonicalPathWithMissingTail(missingTail),
          canonicalPathWithMissingTail(repositoryRoot),
        ),
      /outside the repository/,
    );
  } finally {
    await rm(linkRoot, { recursive: true, force: true });
  }
});

void test("parses exactly one strict --outDir form and rejects malformed aliases", async () => {
  await withFixture(async (root) => {
    assert.equal(parseOutputDirectoryArgument(["--mode", "release", "--outDir", root]), root);
    assert.equal(parseOutputDirectoryArgument([`--outDir=${root}`]), root);

    const invalidArguments = [
      [],
      ["--outDir"],
      ["--outDir", "--mode"],
      ["--outDir", root, "--outDir", root],
      [`--outDir=${root}`, "--outDir", root],
      ["--outDirfoo", root],
      ["--outDirfoo", root, "--outDir", root],
      ["--outDir==/tmp/release"],
      ["--outDir", "relative-output"],
      ["--outDir", "-release"],
    ];

    for (const argumentsList of invalidArguments) {
      assert.throws(() => parseOutputDirectoryArgument(argumentsList), /outDir/);
    }
  });
});

void test("parses exactly one strict --remoteName form and rejects malformed or invalid values", async () => {
  assert.equal(
    parseRemoteNameArgument(["--mode", "release", "--remoteName", "cadence_comms_overview"]),
    "cadence_comms_overview",
  );
  assert.equal(
    parseRemoteNameArgument(["--remoteName=cadence_telemetry_decom"]),
    "cadence_telemetry_decom",
  );

  const invalidArguments = [
    [],
    ["--remoteName"],
    ["--remoteName", "--mode"],
    ["--remoteName", ""],
    ["--remoteName", "cadence_comms_overview", "--remoteName", "cadence_telemetry_decom"],
    ["--remoteName=cadence_comms_overview", "--remoteName", "cadence_telemetry_decom"],
    ["--remoteNamefoo", "cadence_comms_overview"],
    ["--remoteName==cadence_comms_overview"],
    ["--remoteName", "1cadence_remote"],
    ["--remoteName", "cadence/telemetry"],
    ["--remoteName", "a".repeat(129)],
  ];

  for (const argumentsList of invalidArguments) {
    assert.throws(() => parseRemoteNameArgument(argumentsList), /remoteName/);
  }
});

void test("direct CLI invocation binds the expected remote identity independent of cwd", async () => {
  await withFixture(async (root) => {
    const { stdout } = await execFileAsync(
      process.execPath,
      [checkerPath, "--outDir", root, "--remoteName", "fixture_remote"],
      { cwd: root },
    );
    assert.match(stdout, /Release output is relocatable: 13 files checked/);

    const invalidCliArguments = [
      ["--outDir", root],
      ["--outDir", root, "--remoteName", "fixture_remote", "--remoteName", "fixture_remote"],
      ["--outDir", root, "--remoteNamefoo", "fixture_remote"],
      ["--outDir", root, "--remoteName", "1fixture_remote"],
    ];

    for (const argumentsList of invalidCliArguments) {
      await assert.rejects(
        () => execFileAsync(process.execPath, [checkerPath, ...argumentsList], { cwd: root }),
        (error) =>
          error instanceof Error &&
          "code" in error &&
          error.code === 1 &&
          "stderr" in error &&
          typeof error.stderr === "string" &&
          /remoteName/.test(error.stderr),
      );
    }
  });
});

/** @param {Record<string, unknown>} manifest */
function firstExpose(manifest) {
  assert.ok(Array.isArray(manifest.exposes));
  return fixtureRecord(manifest.exposes[0]);
}
/** @param {Record<string, unknown>} manifest @returns {unknown[]} */
function assetImports(manifest) {
  const value = fixtureRecord(fixtureRecord(firstExpose(manifest).assets).js).async;
  assert.ok(Array.isArray(value));
  return value;
}
/** @param {Record<string, unknown>} stats @returns {unknown[]} */
function outputRows(stats) {
  assert.ok(Array.isArray(stats.buildOutput));
  return stats.buildOutput;
}
