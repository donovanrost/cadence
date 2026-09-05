import assert from "node:assert/strict";
import { createHash, generateKeyPairSync, verify } from "node:crypto";
import { spawn } from "node:child_process";
import {
  mkdtemp,
  mkdir,
  readFile,
  readdir,
  realpath,
  rm,
  symlink,
  writeFile,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, describe, it } from "node:test";

import {
  buildRelease,
  buildReleasePayload,
  canonicalJson,
  enumerateArtifacts,
  packageRelease,
  readPrivateKeySource,
  validateRelativeArtifactPath,
} from "./frontend-release-package.mjs";

const TOOL_PATH = fileURLToPath(new URL("./frontend-release-package.mjs", import.meta.url));
const NODE_PATH = process.execPath;
const TEST_ORIGIN = "https://cdn.example.com";

const metadata = {
  application: { id: "telemetry_decom", version: 1 },
  package: { id: "cadence.telemetry-applications", version: 1 },
  surface: { id: "packet_bindings", version: 1 },
  query: { id: "cadence.packet_bindings.manage", version: 1 },
  actions: ["save_packet_bindings"],
  remote: { name: "cadence_telemetry_decom" },
  module: { exposedModule: "./Application" },
  hostCompatibility: {
    hostContract: "cadence.application-host.v1",
    compatibility: {
      cadenceApplicationContract: 1,
      cadenceSurfaceContract: 1,
      cadenceFederatedRendererContract: 1,
      cadenceThemeContract: 1,
    },
    vueRange: "^3.5.40",
  },
  provenance: {
    sourceRepository: "https://github.com/cadence/cadence",
    sourceRevision: "0123456789abcdef0123456789abcdef01234567",
    buildId: "phase-c-test-build",
    builder: "test-runner",
    workflow: "frontend-release",
    builtAt: "2026-08-30T16:00:00Z",
  },
  releasedAt: "2026-08-30T17:00:00Z",
};

const temporaryDirectories = [];

afterEach(async () => {
  await Promise.all(
    temporaryDirectories
      .splice(0)
      .map((directory) => rm(directory, { recursive: true, force: true })),
  );
});

function keyPair() {
  return generateKeyPairSync("ed25519");
}

function privateKeyMaterial(privateKey) {
  return `base64url:${privateKey.export({ format: "der", type: "pkcs8" }).toString("base64url")}`;
}

function sha256(bytes) {
  return `sha256:${createHash("sha256").update(bytes).digest("hex")}`;
}

async function temporaryDirectory(prefix = "cadence-release-package-") {
  const directory = await mkdtemp(join(tmpdir(), prefix));
  temporaryDirectories.push(directory);
  return directory;
}

async function builtRemoteTree() {
  const directory = await temporaryDirectory();
  await mkdir(join(directory, "assets"), { recursive: true });
  for (const [path, bytes] of Object.entries(packageFixtureFiles())) {
    await writeFile(join(directory, path), bytes);
  }
  return directory;
}

function packageFixtureFiles() {
  const files = {
    "assets/app.js": "export const release = 'phase-c';\n",
    "assets/theme.css": ":root { --phase: c; }\n",
    "mf-manifest.json": JSON.stringify({
      id: "cadence_telemetry_decom",
      name: "cadence_telemetry_decom",
      metaData: { publicPath: "auto", remoteEntry: { path: "", name: "remoteEntry.js" } },
      shared: [
        {
          name: "vue",
          assets: { js: { async: [], sync: ["remoteEntry.js"] }, css: { async: [], sync: [] } },
        },
      ],
      exposes: [
        {
          name: "./Application",
          assets: {
            js: { async: [], sync: ["assets/app.js"] },
            css: { async: [], sync: ["assets/theme.css"] },
          },
        },
      ],
    }),
    "mf-stats.json": JSON.stringify({
      buildOutput: [
        { fileName: "assets/app.js" },
        { fileName: "assets/theme.css" },
        { fileName: "remoteEntry.js" },
      ],
    }),
    "remoteEntry.js": "export { default } from './assets/app.js';\n",
  };
  return Object.fromEntries(
    Object.entries(files).map(([path, contents]) => [path, Buffer.from(contents, "utf8")]),
  );
}

async function runCli(argumentsList, environment = {}) {
  return new Promise((resolveResult) => {
    const child = spawn(NODE_PATH, [TOOL_PATH, ...argumentsList], {
      cwd: dirname(dirname(TOOL_PATH)),
      env: { ...process.env, ...environment },
      stdio: ["ignore", "pipe", "pipe"],
    });
    const stdout = [];
    const stderr = [];
    child.stdout.on("data", (chunk) => stdout.push(chunk));
    child.stderr.on("data", (chunk) => stderr.push(chunk));
    child.on("close", (code, signal) =>
      resolveResult({
        code,
        signal,
        stdout: Buffer.concat(stdout).toString("utf8"),
        stderr: Buffer.concat(stderr).toString("utf8"),
      }),
    );
  });
}

void describe("frontend release packager", () => {
  void it("builds a deterministic complete package with the exact release identity and signature", async () => {
    const input = await builtRemoteTree();
    const outputParent = await temporaryDirectory("cadence-release-output-");
    const firstOutput = join(outputParent, "first");
    const secondOutput = join(outputParent, "second");
    const keys = keyPair();

    const first = await packageRelease({
      inputDirectory: input,
      outputDirectory: firstOutput,
      metadata,
      artifactOrigin: TEST_ORIGIN,
      keyId: "fixture-release-key",
      privateKey: keys.privateKey,
    });
    const second = await packageRelease({
      inputDirectory: input,
      outputDirectory: secondOutput,
      metadata,
      artifactOrigin: TEST_ORIGIN,
      keyId: "fixture-release-key",
      privateKey: keys.privateKey,
    });

    assert.equal(first.outputDirectory, join(await realpath(outputParent), "first"));
    assert.deepEqual(first.release, second.release);
    assert.deepEqual(first.documentBytes, second.documentBytes);
    const fixtureFiles = packageFixtureFiles();
    assert.deepEqual(
      first.artifacts.map(({ path, sha256: digest, size, mediaType }) => ({
        path,
        sha256: digest,
        size,
        mediaType,
      })),
      Object.entries(fixtureFiles)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([path, bytes]) => ({
          path,
          sha256: sha256(bytes).slice("sha256:".length),
          size: bytes.byteLength,
          mediaType: path.endsWith(".js")
            ? "application/javascript"
            : path.endsWith(".css")
              ? "text/css"
              : "application/json",
        })),
    );

    const logical = { ...first.release };
    delete logical.releaseId;
    delete logical.artifactBaseUrl;
    assert.equal(first.releaseId, sha256(Buffer.from(canonicalJson(logical), "utf8")));
    assert.equal(
      first.release.artifactBaseUrl,
      `${TEST_ORIGIN}/releases/telemetry_decom/${first.releaseId}/artifacts/`,
    );
    assert.deepEqual(Object.keys(first.release).sort(), [
      "application",
      "artifactBaseUrl",
      "artifacts",
      "exposedModule",
      "hostCompatibility",
      "manifest",
      "package",
      "provenance",
      "releaseId",
      "releasedAt",
      "remoteName",
      "schema",
      "surface",
      "transport",
    ]);
    assert.equal(first.release.manifest.path, "mf-manifest.json");
    assert.equal(first.envelope.payload, first.payloadBytes.toString("base64url"));
    assert.equal(
      verify(
        null,
        Buffer.from(first.envelope.payload, "base64url"),
        keys.publicKey,
        Buffer.from(first.envelope.signature, "base64url"),
      ),
      true,
    );

    const firstEnvelope = await readFile(join(firstOutput, "release.json"));
    assert.deepEqual(firstEnvelope, first.documentBytes);
    for (const artifact of first.artifacts) {
      assert.deepEqual(
        await readFile(join(firstOutput, "artifacts", ...artifact.path.split("/"))),
        artifact.bytes,
      );
      assert.deepEqual(
        await readFile(join(secondOutput, "artifacts", ...artifact.path.split("/"))),
        artifact.bytes,
      );
    }
  });

  void it("matches the repository's canonical JSON and release-ID fixture rules exactly", async () => {
    const corpus = JSON.parse(
      await readFile(
        new URL("../../test/fixtures/frontend_release_catalog_v1.json", import.meta.url),
        "utf8",
      ),
    );
    const payload = JSON.parse(corpus.release.payload);
    assert.equal(canonicalJson(payload), corpus.release.payload);
    const logical = { ...payload };
    delete logical.releaseId;
    delete logical.artifactBaseUrl;
    assert.equal(sha256(Buffer.from(canonicalJson(logical), "utf8")), payload.releaseId);
  });

  void it("accepts the safe environment key contract without exposing the secret", async () => {
    const input = await builtRemoteTree();
    const outputParent = await temporaryDirectory("cadence-release-cli-");
    const metadataFile = join(outputParent, "metadata.json");
    const output = join(outputParent, "package");
    const keys = keyPair();
    await writeFile(metadataFile, JSON.stringify(metadata), { mode: 0o600 });

    const result = await runCli(
      [
        "--",
        "--input-dir",
        input,
        "--metadata",
        metadataFile,
        "--artifact-origin",
        TEST_ORIGIN,
        "--key-id",
        "fixture-release-key",
        "--output-dir",
        output,
      ],
      { CADENCE_RELEASE_PRIVATE_KEY: privateKeyMaterial(keys.privateKey) },
    );

    assert.equal(result.code, 0, result.stderr);
    assert.equal(result.signal, null);
    assert.equal(result.stderr, "");
    assert.ok(!result.stdout.includes(privateKeyMaterial(keys.privateKey)));
    assert.ok(!result.stdout.includes("PRIVATE KEY"));
    assert.equal(JSON.parse(result.stdout).releaseId.startsWith("sha256:"), true);
    assert.deepEqual(
      JSON.parse(await readFile(join(output, "release.json"), "utf8")).keyId,
      "fixture-release-key",
    );
  });

  void it("rejects extra or later CLI option separators", async () => {
    const input = await builtRemoteTree();
    const extra = await runCli(["--", "--"]);
    const later = await runCli(["--input-dir", input, "--"]);

    assert.notEqual(extra.code, 0);
    assert.match(extra.stderr, /unexpected option separator/);
    assert.notEqual(later.code, 0);
    assert.match(later.stderr, /unexpected option separator/);
  });

  void it("rejects secret-bearing failures without printing the key", async () => {
    const input = await temporaryDirectory("cadence-release-invalid-");
    const outputParent = await temporaryDirectory("cadence-release-cli-invalid-");
    const metadataFile = join(outputParent, "metadata.json");
    await writeFile(metadataFile, JSON.stringify(metadata), { mode: 0o600 });
    const secret = privateKeyMaterial(keyPair().privateKey);

    const result = await runCli(
      [
        "--input-dir",
        input,
        "--metadata",
        metadataFile,
        "--artifact-origin",
        TEST_ORIGIN,
        "--key-id",
        "fixture-release-key",
        "--output-dir",
        join(outputParent, "package"),
      ],
      { CADENCE_RELEASE_PRIVATE_KEY: secret },
    );

    assert.notEqual(result.code, 0);
    assert.ok(!result.stdout.includes(secret));
    assert.ok(!result.stderr.includes(secret));
    assert.match(result.stderr, /missing required mf-manifest\.json/);
  });

  void it("fails closed for missing required files, directories, and symlinks", async () => {
    const missingManifest = await temporaryDirectory();
    await writeFile(join(missingManifest, "remoteEntry.js"), "remote");
    await assert.rejects(enumerateArtifacts(missingManifest), /missing required mf-manifest\.json/);

    const directoryManifest = await temporaryDirectory();
    await mkdir(join(directoryManifest, "mf-manifest.json"));
    await writeFile(join(directoryManifest, "remoteEntry.js"), "remote");
    await assert.rejects(
      enumerateArtifacts(directoryManifest),
      /missing required mf-manifest\.json|unexpected or nested directory/,
    );

    const symlinkFile = await builtRemoteTree();
    await symlink(join(symlinkFile, "remoteEntry.js"), join(symlinkFile, "linked.js"));
    await assert.rejects(enumerateArtifacts(symlinkFile), /is a symlink/);

    const symlinkDirectory = await builtRemoteTree();
    await symlink(join(symlinkDirectory, "assets"), join(symlinkDirectory, "linked"));
    await assert.rejects(enumerateArtifacts(symlinkDirectory), /is a symlink/);
  });

  void it("rejects a symlinked output parent without mutating the input tree", async () => {
    const input = await builtRemoteTree();
    const outputContainer = await temporaryDirectory("cadence-release-symlink-output-");
    const symlinkedParent = join(outputContainer, "output-parent");
    const output = join(symlinkedParent, "package");
    await symlink(input, symlinkedParent);

    const before = await enumerateArtifacts(input);
    const beforeEntries = (await readdir(input)).sort();

    await assert.rejects(
      packageRelease({
        inputDirectory: input,
        outputDirectory: output,
        metadata,
        artifactOrigin: TEST_ORIGIN,
        keyId: "fixture-release-key",
        privateKey: keyPair().privateKey,
      }),
      /must not overlap the input tree/,
    );

    const after = await enumerateArtifacts(input);
    assert.deepEqual((await readdir(input)).sort(), beforeEntries);
    assert.deepEqual(
      after.artifacts.map(({ path, sha256: digest, size, mediaType, bytes }) => ({
        path,
        sha256: digest,
        size,
        mediaType,
        bytes,
      })),
      before.artifacts.map(({ path, sha256: digest, size, mediaType, bytes }) => ({
        path,
        sha256: digest,
        size,
        mediaType,
        bytes,
      })),
    );
    await assert.rejects(readFile(output), /ENOENT/);
    await assert.rejects(readFile(join(input, "package", "release.json")), /ENOENT/);
  });

  void it("rejects a symlinked private-key path before opening it", async () => {
    const directory = await temporaryDirectory("cadence-release-key-race-");
    const keyPath = join(directory, "key.der");
    const linkPath = join(directory, "key-link.der");
    const keys = keyPair();
    await writeFile(keyPath, keys.privateKey.export({ format: "der", type: "pkcs8" }), {
      mode: 0o600,
    });
    await symlink(keyPath, linkPath);

    await assert.rejects(
      readPrivateKeySource({ privateKeyFile: linkPath }),
      /regular non-symlink file/,
    );
  });

  void it("rejects absolute, traversal, backslash, drive, and unnormalized paths", () => {
    for (const path of [
      "/absolute.js",
      "../escape.js",
      "assets/../escape.js",
      "assets//app.js",
      "assets\\app.js",
      "C:app.js",
    ]) {
      assert.throws(
        () => validateRelativeArtifactPath(path),
        /relative|forbidden|traversal|normalized/,
      );
    }
  });

  void it("rejects malformed identities and duplicate normalized inventory paths", async () => {
    const input = await builtRemoteTree();
    const inventory = await enumerateArtifacts(input);
    const duplicateInventory = {
      ...inventory,
      artifacts: [...inventory.artifacts, { ...inventory.artifacts[0] }],
    };
    assert.throws(
      () =>
        buildReleasePayload({
          inventory: duplicateInventory,
          metadata,
          artifactOrigin: TEST_ORIGIN,
        }),
      /duplicate normalized artifact path/,
    );

    const malformed = { ...metadata, application: { id: "../telemetry", version: 1 } };
    assert.throws(
      () =>
        buildReleasePayload({
          inventory,
          metadata: malformed,
          artifactOrigin: TEST_ORIGIN,
        }),
      /application\.id is not a safe identifier/,
    );
  });

  void it("rejects artifact bytes whose size or digest does not match the inventory", async () => {
    const input = await builtRemoteTree();
    const inventory = await enumerateArtifacts(input);
    const original = inventory.artifacts.find(({ path }) => path === "assets/app.js");
    const changedBytes = Buffer.from("export const release = 'phase-d';\n", "utf8");
    assert.equal(changedBytes.byteLength, original.bytes.byteLength);

    const changedInventory = {
      ...inventory,
      artifacts: inventory.artifacts.map((artifact) =>
        artifact.path === original.path ? { ...artifact, bytes: changedBytes } : artifact,
      ),
    };
    assert.throws(
      () =>
        buildReleasePayload({
          inventory: changedInventory,
          metadata,
          artifactOrigin: TEST_ORIGIN,
        }),
      /digest does not match bytes/,
    );

    const mismatchedSizeInventory = {
      ...inventory,
      artifacts: inventory.artifacts.map((artifact) =>
        artifact.path === original.path ? { ...artifact, size: artifact.size + 1 } : artifact,
      ),
    };
    assert.throws(
      () =>
        buildReleasePayload({
          inventory: mismatchedSizeInventory,
          metadata,
          artifactOrigin: TEST_ORIGIN,
        }),
      /artifact size does not match bytes/,
    );
  });

  void it("validates and packages one frozen byte snapshot across a deterministic disk swap", async () => {
    const input = await builtRemoteTree();
    const outputParent = await temporaryDirectory("cadence-release-snapshot-output-");
    const output = join(outputParent, "package");
    const appPath = join(input, "assets", "app.js");
    const laterPath = join(input, "assets", "later-added.js");
    const originalBytes = await readFile(appPath);
    const swappedBytes = Buffer.from("export const release = 'swapped';\n", "utf8");
    assert.equal(swappedBytes.byteLength, originalBytes.byteLength);

    const result = await packageRelease({
      inputDirectory: input,
      outputDirectory: output,
      metadata,
      artifactOrigin: TEST_ORIGIN,
      keyId: "fixture-release-key",
      privateKey: keyPair().privateKey,
      afterSnapshot: async () => {
        await writeFile(appPath, swappedBytes);
        await writeFile(laterPath, "export const later = true;\n");
      },
    });

    assert.deepEqual(
      await readFile(join(output, "artifacts", "assets", "app.js")),
      originalBytes,
    );
    assert.deepEqual(
      result.artifacts.find(({ path }) => path === "assets/app.js").bytes,
      originalBytes,
    );
    assert.deepEqual(await readFile(appPath), swappedBytes);
    await assert.rejects(
      readFile(join(output, "artifacts", "assets", "later-added.js")),
      /ENOENT/,
    );
  });

  void it("rejects empty and nested input directories as exact-tree violations", async () => {
    const empty = await builtRemoteTree();
    await mkdir(join(empty, "empty-directory"));
    await assert.rejects(
      enumerateArtifacts(empty),
      /unexpected or nested directory empty-directory/,
    );

    const nested = await builtRemoteTree();
    await mkdir(join(nested, "assets", "nested"));
    await writeFile(
      join(nested, "assets", "nested", "asset.js"),
      "export const nested = true;\n",
    );
    await assert.rejects(
      enumerateArtifacts(nested),
      /unexpected or nested directory assets\/nested/,
    );
  });

  void it("keeps the package output outside the repository and requires explicit metadata", async () => {
    const input = await builtRemoteTree();
    await assert.rejects(
      packageRelease({
        inputDirectory: input,
        outputDirectory: join(dirname(TOOL_PATH), "generated-release"),
        metadata,
        artifactOrigin: TEST_ORIGIN,
        keyId: "fixture-release-key",
        privateKey: keyPair().privateKey,
      }),
      /outside the repository/,
    );
    const incomplete = { ...metadata };
    delete incomplete.releasedAt;
    await assert.rejects(
      buildRelease({
        inputDirectory: input,
        metadata: incomplete,
        artifactOrigin: TEST_ORIGIN,
        keyId: "fixture-release-key",
        privateKey: keyPair().privateKey,
      }),
      /unexpected or missing field/,
    );
  });

  void it("leaves an existing output destination immutable", async () => {
    const input = await builtRemoteTree();
    const outputParent = await temporaryDirectory("cadence-release-existing-output-");
    const output = join(outputParent, "package");
    await mkdir(output);
    await writeFile(join(output, "keep.txt"), "keep this destination immutable\n");

    await assert.rejects(
      packageRelease({
        inputDirectory: input,
        outputDirectory: output,
        metadata,
        artifactOrigin: TEST_ORIGIN,
        keyId: "fixture-release-key",
        privateKey: keyPair().privateKey,
      }),
      /already exists; choose a new immutable destination/,
    );
    assert.deepEqual(await readdir(output), ["keep.txt"]);
    assert.equal(
      await readFile(join(output, "keep.txt"), "utf8"),
      "keep this destination immutable\n",
    );
  });
});
