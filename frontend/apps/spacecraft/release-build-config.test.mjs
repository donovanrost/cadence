import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { lstat, mkdtemp, readFile, readdir, rm, symlink, writeFile } from "node:fs/promises";
import test from "node:test";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";

const appRoot = resolve(import.meta.dirname);
const repositoryRoot = resolve(appRoot, "../../..");
const vitePlusEntry = resolve(appRoot, "node_modules/vite-plus/bin/vp");
const outputEnvironmentName = "CADENCE_RELEASE_OUTPUT_DIR";
const identityEnvironmentNames = [
  "MF_BUILD_ID",
  "MF_BUILD_VERSION",
  "MF_VERSION",
  "BUILD_ID",
  "BUILD_VERSION",
  "RELEASE_ID",
  "RELEASE_VERSION",
];

async function withTemporaryDirectory(callback) {
  const directory = await mkdtemp(join(tmpdir(), "cadence-spacecraft-release-config-"));
  try {
    return await callback(directory);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

function runVite(argumentsList, environment = {}) {
  const childEnvironment = { ...process.env };
  for (const name of identityEnvironmentNames) delete childEnvironment[name];
  for (const [name, value] of Object.entries(environment)) {
    if (value === undefined) delete childEnvironment[name];
    else childEnvironment[name] = value;
  }
  childEnvironment.PATH = `${dirname(process.execPath)}:${childEnvironment.PATH ?? ""}`;

  return new Promise((resolveResult, reject) => {
    const child = spawn(process.execPath, [vitePlusEntry, ...argumentsList], {
      cwd: appRoot,
      env: childEnvironment,
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

function releaseArguments(...argumentsList) {
  return [
    "build",
    "--config",
    resolve(appRoot, "vite.config.ts"),
    "--mode",
    "release",
    ...argumentsList,
  ];
}

async function pathExists(path) {
  try {
    await lstat(path);
    return true;
  } catch (error) {
    if (error?.code === "ENOENT" || error?.code === "ENOTDIR") return false;
    throw error;
  }
}

async function assertRejectedProbe({ argumentsList, environment, absentPath, message }) {
  assert.equal(await pathExists(absentPath), false, `${message}: probe target already exists`);
  const result = await runVite(releaseArguments(...argumentsList), environment);
  assert.notEqual(result.code, 0, `${message}: probe unexpectedly succeeded`);
  assert.match(
    `${result.stdout}\n${result.stderr}`,
    /CADENCE_RELEASE_OUTPUT_DIR|outDir|Release build output|release-identity/,
    message,
  );
  assert.equal(
    await pathExists(absentPath),
    false,
    `${message}: rejected probe created its target`,
  );
  return result;
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

void test("emits only the federation release graph into clean external directories", async () => {
  await withTemporaryDirectory(async (root) => {
    const alias = join(root, "external-alias");
    await symlink(root, alias, "dir");
    const aliasedOutput = join(alias, "nested", "release");
    const canonicalOutput = join(root, "nested", "release");
    const secondOutput = join(root, "nested", "second-release");

    const result = await runVite(releaseArguments("--outDir", canonicalOutput), {
      [outputEnvironmentName]: aliasedOutput,
    });

    assert.equal(result.code, 0, result.stderr);
    assert.equal(await pathExists(canonicalOutput), true);
    for (const required of ["mf-manifest.json", "mf-stats.json", "remoteEntry.js"]) {
      assert.equal(await pathExists(join(canonicalOutput, required)), true, required);
    }
    const manifest = JSON.parse(await readFile(join(canonicalOutput, "mf-manifest.json"), "utf8"));
    assert.deepEqual(
      manifest.exposes.map(({ path }) => path),
      ["./Application"],
    );
    const stats = JSON.parse(await readFile(join(canonicalOutput, "mf-stats.json"), "utf8"));
    assert.equal(Object.hasOwn(stats, "assetAnalysis"), false);
    assert.equal(await pathExists(join(canonicalOutput, "index.html")), false);
    assert.equal(await pathExists(join(canonicalOutput, ".vite/manifest.json")), false);

    const emittedPaths = await outputFiles(canonicalOutput);
    assert.equal(
      emittedPaths.some((path) => /(?:^|\/)index-[^/]+\.js$/.test(path)),
      false,
    );
    assert.equal(
      emittedPaths.some((path) => path.includes("failure-application")),
      false,
    );
    for (const path of emittedPaths) {
      const bytes = await readFile(path);
      assert.equal(
        bytes.includes(Buffer.from(aliasedOutput)),
        false,
        relative(canonicalOutput, path),
      );
      assert.equal(
        bytes.includes(Buffer.from("MF_BUILD_ID")),
        false,
        relative(canonicalOutput, path),
      );
      assert.equal(
        bytes.includes(Buffer.from("2026.08.22")),
        false,
        relative(canonicalOutput, path),
      );
    }

    const secondResult = await runVite(releaseArguments("--outDir", secondOutput), {
      [outputEnvironmentName]: secondOutput,
    });
    assert.equal(secondResult.code, 0, secondResult.stderr);
    const secondPaths = await outputFiles(secondOutput);
    assert.deepEqual(
      emittedPaths.map((path) => relative(canonicalOutput, path)),
      secondPaths.map((path) => relative(secondOutput, path)),
    );

    const stalePath = join(secondOutput, "assets", "stale-release.js");
    await writeFile(stalePath, "export const stale = true;\n");
    const rebuiltResult = await runVite(releaseArguments("--outDir", secondOutput), {
      [outputEnvironmentName]: secondOutput,
    });
    assert.equal(rebuiltResult.code, 0, rebuiltResult.stderr);
    assert.equal(await pathExists(stalePath), false, "stale output survived the release rebuild");
  });
});

void test("keeps standalone entry behavior outside release mode", async () => {
  await withTemporaryDirectory(async (root) => {
    const output = join(root, "standalone");
    const result = await runVite(
      [
        "build",
        "--config",
        resolve(appRoot, "vite.config.ts"),
        "--mode",
        "development",
        "--outDir",
        output,
      ],
      {},
    );
    assert.equal(result.code, 0, result.stderr);
    assert.equal(await pathExists(join(output, "index.html")), true);
  });
});

void test("rejects missing, malformed, relative, option-like, and duplicate outDir forms before writes", async () => {
  await withTemporaryDirectory(async (root) => {
    const missingEnvironmentOutput = join(root, "missing-environment-cli-output");
    await assertRejectedProbe({
      argumentsList: ["--outDir", missingEnvironmentOutput],
      environment: { [outputEnvironmentName]: undefined },
      absentPath: missingEnvironmentOutput,
      message: "missing CADENCE_RELEASE_OUTPUT_DIR",
    });

    const relativeEnvironmentOutput = join(root, "relative-environment-cli-output");
    await assertRejectedProbe({
      argumentsList: ["--outDir", relativeEnvironmentOutput],
      environment: { [outputEnvironmentName]: "relative-output" },
      absentPath: relativeEnvironmentOutput,
      message: "relative CADENCE_RELEASE_OUTPUT_DIR",
    });

    const output = join(root, "missing-cli-output");
    const environment = { [outputEnvironmentName]: output };

    await assertRejectedProbe({
      argumentsList: [],
      environment,
      absentPath: output,
      message: "missing --outDir",
    });
    await assertRejectedProbe({
      argumentsList: ["--outDir", "relative-output"],
      environment,
      absentPath: output,
      message: "relative --outDir",
    });
    await assertRejectedProbe({
      argumentsList: ["--outDir", "--mode"],
      environment,
      absentPath: output,
      message: "option-like --outDir",
    });
    await assertRejectedProbe({
      argumentsList: ["--outDir==/tmp/release"],
      environment,
      absentPath: output,
      message: "malformed --outDir",
    });
    await assertRejectedProbe({
      argumentsList: ["--outDirfoo", output],
      environment,
      absentPath: output,
      message: "malformed --outDir alias",
    });
    await assertRejectedProbe({
      argumentsList: ["--outDir", output, "--outDir", output],
      environment,
      absentPath: output,
      message: "duplicate --outDir",
    });
  });
});

void test("rejects canonical env/CLI mismatch and repository overlap before writes", async () => {
  await withTemporaryDirectory(async (root) => {
    const environmentOutput = join(root, "environment-output");
    const cliOutput = join(root, "cli-output");
    await assertRejectedProbe({
      argumentsList: ["--outDir", cliOutput],
      environment: { [outputEnvironmentName]: environmentOutput },
      absentPath: environmentOutput,
      message: "environment/CLI mismatch",
    });
    assert.equal(await pathExists(cliOutput), false);

    const repositoryChild = join(repositoryRoot, ".spacecraft-release-rejected");
    await assertRejectedProbe({
      argumentsList: ["--outDir", repositoryChild],
      environment: { [outputEnvironmentName]: repositoryChild },
      absentPath: repositoryChild,
      message: "repository child",
    });

    const repositoryAliasRoot = join(root, "repository-alias");
    await symlink(repositoryRoot, repositoryAliasRoot, "dir");
    const symlinkChild = join(repositoryAliasRoot, ".spacecraft-release-symlink-rejected");
    await assertRejectedProbe({
      argumentsList: ["--outDir", symlinkChild],
      environment: { [outputEnvironmentName]: symlinkChild },
      absentPath: symlinkChild,
      message: "repository symlink alias",
    });

    const repositoryBefore = await lstat(repositoryRoot);
    const repositoryResult = await runVite(releaseArguments("--outDir", repositoryRoot), {
      [outputEnvironmentName]: repositoryRoot,
    });
    assert.notEqual(repositoryResult.code, 0);
    assert.match(
      `${repositoryResult.stdout}\n${repositoryResult.stderr}`,
      /outside the repository/,
    );
    const repositoryAfter = await lstat(repositoryRoot);
    assert.equal(repositoryAfter.ino, repositoryBefore.ino, "repository target was replaced");

    const ancestor = dirname(repositoryRoot);
    const ancestorBefore = await lstat(ancestor);
    const ancestorResult = await runVite(releaseArguments("--outDir", ancestor), {
      [outputEnvironmentName]: ancestor,
    });
    assert.notEqual(ancestorResult.code, 0);
    assert.match(`${ancestorResult.stdout}\n${ancestorResult.stderr}`, /outside the repository/);
    const ancestorAfter = await lstat(ancestor);
    assert.equal(ancestorAfter.ino, ancestorBefore.ino, "repository ancestor target was replaced");
  });
});

void test("rejects a non-directory parent before Vite can create the target", async () => {
  await withTemporaryDirectory(async (root) => {
    const nonDirectoryParent = join(root, "not-a-directory");
    await writeFile(nonDirectoryParent, "parent file\n");
    const output = join(nonDirectoryParent, "release");

    await assertRejectedProbe({
      argumentsList: ["--outDir", output],
      environment: { [outputEnvironmentName]: output },
      absentPath: output,
      message: "non-directory parent",
    });
  });
});

void test("rejects every release identity environment injection before writes", async () => {
  await withTemporaryDirectory(async (root) => {
    for (const [index, name] of identityEnvironmentNames.entries()) {
      const output = join(root, `identity-rejected-${index}`);
      await assertRejectedProbe({
        argumentsList: ["--outDir", output],
        environment: {
          [outputEnvironmentName]: output,
          [name]: "injected-release-identity",
        },
        absentPath: output,
        message: name,
      });
    }
  });
});
