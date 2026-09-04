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

void test("scans quoted and unquoted JavaScript and CSS references", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "remoteEntry.js"), 'import "../outside.js";\n');
    await expectCheckFailure(root, "fixture_remote", /escapes the output/);
  });

  await withFixture(async (root) => {
    assert.doesNotThrow(() => parseOutputDirectoryArgument(["--outDir", root]));
    await validateReleaseOutput(root, "fixture_remote", repositoryRoot);
  });
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
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.exposes[0].assets.js.async = ["assets/missing.js"];
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, "fixture_remote", /points to missing/);
  });

  await withFixture(async (root) => {
    const statsPath = join(root, "mf-stats.json");
    const stats = JSON.parse(await readFile(statsPath, "utf8"));
    stats.buildOutput.push({ fileName: "assets/missing.js" });
    await writeFile(statsPath, JSON.stringify(stats));
    await expectCheckFailure(root, "fixture_remote", /points to missing/);
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
    const manifestPath = join(root, "mf-manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest.exposes[0].path = "./Failure";
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
        (error) => error.code === 1 && /remoteName/.test(error.stderr),
      );
    }
  });
});
