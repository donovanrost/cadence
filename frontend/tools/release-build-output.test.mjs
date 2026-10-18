import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { dirname, join, resolve } from "node:path";
import test from "node:test";
import { resolveConfig } from "vite-plus";
import { releaseBuildOutput, releaseOutputGuard } from "./release-build-output.mjs";

const repository = resolve(import.meta.dirname, "../..");
const apps = [
  "organization-admin",
  "mission-catalog",
  "spacecraft",
  "telemetry-decom",
  "comms-overview",
  "ops-console",
];

void test("all remotes reject unsafe release paths before output cleanup", async () => {
  const directory = await mkdtemp(join(tmpdir(), "cadence-release-preflight-"));
  const previous = process.env.CADENCE_RELEASE_OUTPUT_DIR;
  const argv = process.argv;
  try {
    await writeFile(join(directory, "sentinel"), "preserve");
    const alias = join(directory, "repository");
    await symlink(repository, alias, "dir");
    for (const app of apps) {
      for (const output of [
        repository,
        dirname(repository),
        join(repository, "missing-output"),
        join(alias, "missing-output"),
      ]) {
        process.env.CADENCE_RELEASE_OUTPUT_DIR = output;
        process.argv = [...argv.slice(0, 2), "build", "--outDir", output];
        await assert.rejects(
          resolveConfig(
            {
              root: resolve(repository, "frontend/apps", app),
              configFile: resolve(repository, "frontend/apps", app, "vite.config.ts"),
              mode: "release",
              logLevel: "silent",
            },
            "build",
          ),
          /outside the repository/,
          app,
        );
      }
    }
    assert.equal(await readFile(join(directory, "sentinel"), "utf8"), "preserve");
  } finally {
    process.argv = argv;
    if (previous === undefined) delete process.env.CADENCE_RELEASE_OUTPUT_DIR;
    else process.env.CADENCE_RELEASE_OUTPUT_DIR = previous;
    await rm(directory, { recursive: true, force: true });
  }
});

void test("preflight admits equivalent external paths and rejects overrides and malformed paths without writing", async () => {
  const directory = await mkdtemp(join(tmpdir(), "cadence-release-paths-"));
  try {
    await writeFile(join(directory, "sentinel"), "preserve");
    const alias = join(directory, "alias");
    await symlink(directory, alias, "dir");
    const output = join(directory, "new", "release");
    const options = {
      environment: { CADENCE_RELEASE_OUTPUT_DIR: join(alias, "new", "release") },
      argumentsList: ["--outDir", output],
    };
    const accepted = releaseBuildOutput({ command: "build", mode: "release" }, options);
    assert.ok(accepted);
    const guard = releaseOutputGuard(accepted);
    assert.doesNotThrow(() =>
      guard.configResolved({ root: repository, build: { outDir: output } }),
    );
    for (const outDir of [repository, "frontend", join(directory, "different")])
      assert.throws(() => guard.configResolved({ root: repository, build: { outDir } }));
    for (const argumentsList of [
      [],
      ["--outDir", "relative"],
      ["--outDir", output, "--outDir", output],
      ["--outDir", directory],
    ])
      assert.throws(() =>
        releaseBuildOutput({ command: "build", mode: "release" }, { ...options, argumentsList }),
      );
    assert.equal(releaseBuildOutput({ command: "build", mode: "publication" }), undefined);
    assert.equal(await readFile(join(directory, "sentinel"), "utf8"), "preserve");
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
