import assert from "node:assert/strict";
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import {
  assertOutputOutsideRepository,
  canonicalPathWithMissingTail,
  parseOutputDirectoryArgument,
  pathsOverlap,
  validateReleaseOutput,
} from "./frontend-release-output-check.mjs";

const repositoryRoot = resolve(import.meta.dirname, "../..");

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
      id: "cadence_comms_overview",
      name: "cadence_comms_overview",
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

async function withFixture(callback, baseDirectory = tmpdir()) {
  const root = await makeFixture(baseDirectory);
  try {
    return await callback(root);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

async function expectCheckFailure(root, pattern) {
  await assert.rejects(() => validateReleaseOutput(root, repositoryRoot), pattern);
}

void test("accepts the complete release reference closure, including comments and external URLs", async () => {
  await withFixture(async (root) => {
    const result = await validateReleaseOutput(root, repositoryRoot);
    assert.equal(result.fileCount > 0, true);
  });
});

void test("resolves the actual Cadence repository root from the shared tools path", async () => {
  await withFixture(async (root) => {
    const result = await validateReleaseOutput(root);
    assert.equal(result.fileCount > 0, true);
  }, dirname(repositoryRoot));
});

void test("scans quoted and unquoted references while keeping query and fragment URLs on the current document", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "remoteEntry.js"), 'import "../outside.js";\n');
    await expectCheckFailure(root, /escapes the output/);
  });

  await withFixture(async (root) => {
    const html = await readFile(join(root, "index.html"), "utf8");
    assert.match(html, /src=assets\/image\.svg/);
    assert.doesNotThrow(() => parseOutputDirectoryArgument(["--outDir", root]));
    await validateReleaseOutput(root, repositoryRoot);
  });
});

void test("rejects a real CSS or HTML reference that is absent", async () => {
  await withFixture(async (root) => {
    await writeFile(join(root, "assets/style.css"), '.real { background: url("./missing.png"); }');
    await expectCheckFailure(root, /CSS URL points to missing/);
  });

  await withFixture(async (root) => {
    await writeFile(join(root, "index.html"), "<img src=assets/missing.svg>");
    await expectCheckFailure(root, /HTML reference points to missing/);
  });
});

void test("requires manifest imports and dynamicImports to be manifest keys with existing transitive files", async () => {
  await withFixture(async (root) => {
    const manifestPath = join(root, ".vite/manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest["src/main.js"].dynamicImports = ["chunks/missing.js"];
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, /references missing manifest key/);
  });

  await withFixture(async (root) => {
    const manifestPath = join(root, ".vite/manifest.json");
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    manifest["chunks/chunk.js"].file = "chunks/missing.js";
    await writeFile(manifestPath, JSON.stringify(manifest));
    await expectCheckFailure(root, /\.file points to missing/);
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
      ["--outDir==/tmp/release"],
      ["--outDir", "relative-output"],
      ["--outDir", "-release"],
    ];

    for (const argumentsList of invalidArguments) {
      assert.throws(() => parseOutputDirectoryArgument(argumentsList), /outDir/);
    }
  });
});
