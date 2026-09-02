import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import { promisify } from "node:util";
import {
  assertOutputOutsideRepository,
  canonicalPathWithMissingTail,
  parseRemoteNameArgument,
  parseOutputDirectoryArgument,
  pathsOverlap,
  validateReleaseOutput,
} from "./frontend-release-output-check.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../..");
const checkerPath = resolve(import.meta.dirname, "frontend-release-output-check.mjs");
const execFileAsync = promisify(execFile);

async function makeFixture(baseDirectory = tmpdir()) {
  const root = await mkdtemp(join(baseDirectory, "cadence-frontend-release-check-"));
  const assets = join(root, "assets");
  await mkdir(assets, { recursive: true });

  const files = {
    "remoteEntry.js": `
      import "./quoted.js";
      import \`./backtick.js\`;
      import "./side-effect.js";
      export { value } from "./exported.js";
      const loaded = import("./dynamic.js");
      const icon = new URL("./assets/image.svg", import.meta.url);
      import "https://cdn.example.test/remote.js";
      import "//cdn.example.test/remote.js";
      const text = "import('./missing-string.js')";
      // import("./missing-line-comment.js")
      /* import("./missing-block-comment.js") */
      const member = object.import("./missing-member-call.js");
      void loaded; void icon; void member;
    `,
    "quoted.js": "export const quoted = true;\n",
    "backtick.js": "export const backtick = true;\n",
    "side-effect.js": "globalThis.sideEffect = true;\n",
    "exported.js": "export const value = true;\n",
    "dynamic.js": "export const dynamic = true;\n",
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
    "index.html": `
      <!-- <img src="./missing-comment.html"> -->
      <div title="src='./missing-string.html'">literal text</div>
      <img src=assets/image.svg>
      <link href="./assets/style.css">
      <script src="?cache=1">const text = '<img src="./missing-script.html">';</script>
      <a href=#top>top</a>
      <a href="https://example.test/docs">external</a>
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
            js: { async: ["dynamic.js"], sync: ["remoteEntry.js"] },
            css: { async: [], sync: ["assets/style.css"] },
          },
        },
      ],
    }),
    "mf-stats.json": JSON.stringify({ buildOutput: [{ fileName: "remoteEntry.js" }] }),
    ".vite/manifest.json": JSON.stringify({
      "src/main.js": {
        file: "remoteEntry.js",
        imports: ["chunks/chunk.js"],
        dynamicImports: ["chunks/dynamic.js"],
        css: ["assets/style.css"],
        assets: ["assets/image.svg"],
      },
      "chunks/chunk.js": {
        file: "quoted.js",
        imports: [],
        dynamicImports: [],
        css: [],
        assets: [],
      },
      "chunks/dynamic.js": {
        file: "dynamic.js",
        imports: [],
        dynamicImports: [],
        css: [],
        assets: [],
      },
    }),
  };

  for (const [path, contents] of Object.entries(files)) {
    const target = join(root, path);
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, contents);
  }

  return root;
}

async function setManifestIdentity(root, id, name = id) {
  const manifestPath = join(root, "mf-manifest.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  manifest.id = id;
  manifest.name = name;
  await writeFile(manifestPath, JSON.stringify(manifest));
}

async function withFixture(callback, baseDirectory = tmpdir()) {
  const root = await makeFixture(baseDirectory);
  try {
    return await callback(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function expectCheckFailure(root, expectedRemoteName, pattern) {
  await assert.rejects(
    () => validateReleaseOutput(root, expectedRemoteName, repositoryRoot),
    pattern,
  );
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

void test("scans quoted and unquoted references while keeping query and fragment URLs on the current document", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "remoteEntry.js"), 'import "../outside.js";\n');
    await expectCheckFailure(root, "fixture_remote", /escapes the output/);
  });

  await withFixture(async (root) => {
    const html = await readFile(join(root, "index.html"), "utf8");
    assert.match(html, /src=assets\/image\.svg/);
    assert.doesNotThrow(() => parseOutputDirectoryArgument(["--outDir", root]));
    await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
  });
});

void test("rejects a real CSS or HTML reference that is absent", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "assets/style.css"), '.real { background: url("./missing.png"); }');
    await expectCheckFailure(root, "fixture_remote", /CSS URL points to missing/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "index.html"), "<img src=assets/missing.svg>");
    await expectCheckFailure(root, "fixture_remote", /HTML reference points to missing/);
  });
});

void test("requires manifest imports and dynamicImports to be manifest keys with existing transitive files", async () => {
  await withFixture(async (root) => {
    const manifestPath = join(root, ".vite/manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest["src/main.js"].dynamicImports = ["chunks/missing.js"];
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, "fixture_remote", /references missing manifest key/);
  });

  await withFixture(async (root) => {
    const manifestPath = join(root, ".vite/manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest["chunks/chunk.js"].file = "chunks/missing.js";
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, "fixture_remote", /\.file points to missing/);
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
    assert.match(stdout, /Release output is relocatable: 15 files checked/);

    const invalidCliArguments = [
      ["--outDir", root],
      ["--outDir", root, "--remoteName", "fixture_remote", "--remoteName", "fixture_remote"],
      ["--outDir", root, "--remoteNamefoo", "fixture_remote"],
      ["--outDir", root, "--remoteName", "1fixture_remote"],
    ];

    for (const argumentsList of invalidCliArguments) {
      await assert.rejects(
        () => execFileAsync(process.execPath, [checkerPath, ...argumentsList], { cwd: root }),
        (error) => error.code === 1 && /remoteName/.test(error.stderr),
      );
    }
  });
});
