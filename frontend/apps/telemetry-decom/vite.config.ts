import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { lstatSync, realpathSync, statSync } from "node:fs";
import { basename, dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const releaseFederationConfig = {
  ...federationConfig,
  exposes: { "./Application": federatedEntry },
  manifest: {
    additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
      if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
      const publicationStats = { ...stats };
      delete publicationStats.assetAnalysis;
      return publicationStats;
    },
  },
};
const repositoryRoot = realpathSync(resolve(__dirname, "../../.."));
const releaseOutputEnvironmentName = "CADENCE_RELEASE_OUTPUT_DIR";

const releaseIdentityEnvironmentNames = [
  "MF_BUILD_ID",
  "MF_BUILD_VERSION",
  "MF_VERSION",
  "BUILD_ID",
  "BUILD_VERSION",
  "RELEASE_ID",
  "RELEASE_VERSION",
];

function errorCode(error: unknown) {
  return error && typeof error === "object" && "code" in error ? error.code : undefined;
}

function releaseOutputDirectory() {
  const configuredOutput = process.env[releaseOutputEnvironmentName];

  if (!configuredOutput || !isAbsolute(configuredOutput)) {
    throw new Error(
      `${releaseOutputEnvironmentName} must be an absolute output directory outside the repository.`,
    );
  }

  const outputDirectory = canonicalPathWithMissingTail(configuredOutput);
  const argumentOutputDirectory = canonicalPathWithMissingTail(
    parseReleaseOutputArgument(process.argv.slice(2)),
  );
  if (outputDirectory !== argumentOutputDirectory) {
    throw new Error(`${releaseOutputEnvironmentName} must match --outDir.`);
  }

  assertOutputOutsideRepository(outputDirectory, repositoryRoot);

  return outputDirectory;
}

function parseReleaseOutputArgument(argumentsList: string[]) {
  const values: string[] = [];

  for (let index = 0; index < argumentsList.length; index += 1) {
    const argument = argumentsList[index];
    let value: string | undefined;

    if (argument === "--outDir") {
      value = argumentsList[index + 1];
      index += 1;
      if (!value || value.startsWith("-")) {
        throw new Error("Release builds require one absolute, non-option --outDir value.");
      }
    } else if (argument.startsWith("--outDir=")) {
      value = argument.slice("--outDir=".length);
      if (!value || value.startsWith("-")) {
        throw new Error("Release builds require one absolute, non-option --outDir value.");
      }
    } else {
      if (argument.startsWith("--outDir")) {
        throw new Error("Release builds require one absolute, non-option --outDir value.");
      }
      continue;
    }

    if (!isAbsolute(value)) {
      throw new Error("Release builds require one absolute, non-option --outDir value.");
    }
    values.push(value);
  }

  if (values.length !== 1) {
    throw new Error("Release builds require exactly one --outDir with one value.");
  }

  return values[0];
}

function canonicalPathWithMissingTail(path: string) {
  const missingTail: string[] = [];
  let current = resolve(path);

  while (true) {
    let canonicalExisting: string;
    try {
      canonicalExisting = realpathSync(current);
    } catch (error) {
      if (errorCode(error) !== "ENOENT") {
        throw new Error("Release build output cannot be resolved.", { cause: error });
      }

      let existingEntry;
      try {
        existingEntry = lstatSync(current);
      } catch (lstatError) {
        if (errorCode(lstatError) !== "ENOENT") {
          throw new Error("Release build output cannot be resolved.", { cause: lstatError });
        }
      }

      if (existingEntry) {
        throw new Error("Release build output cannot resolve a path component.");
      }

      const parent = dirname(current);
      if (parent === current) throw new Error("Release build output cannot be resolved.");
      missingTail.push(basename(current));
      current = parent;
      continue;
    }

    const existingStats = statSync(canonicalExisting);
    if (!existingStats.isDirectory()) {
      throw new Error(
        missingTail.length > 0
          ? "Release build output has a non-directory parent."
          : "Release build output must be a directory.",
      );
    }
    return resolve(canonicalExisting, ...missingTail.reverse());
  }
}

function assertOutputOutsideRepository(outputRoot: string, canonicalRepositoryRoot: string) {
  const contains = (parent: string, child: string) => {
    const childRelative = relative(parent, child);
    return (
      childRelative === "" ||
      (childRelative !== ".." &&
        !childRelative.startsWith(`..${sep}`) &&
        !isAbsolute(childRelative))
    );
  };

  if (
    contains(canonicalRepositoryRoot, outputRoot) ||
    contains(outputRoot, canonicalRepositoryRoot)
  ) {
    throw new Error("Release build output must be outside the repository in both directions.");
  }
}

function releaseOutputPlugin() {
  return {
    name: "cadence-telemetry-decom-release-output",
    enforce: "post",
    apply: "build",
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const releaseBuild = mode === "release";

  if (releaseBuild && command !== "build") {
    throw new Error("The release mode is available only for production builds.");
  }

  const outputDirectory = releaseBuild ? releaseOutputDirectory() : undefined;

  if (
    releaseBuild &&
    releaseIdentityEnvironmentNames.some((name) => Object.hasOwn(process.env, name))
  ) {
    throw new Error("Release builds do not accept release-identity environment injection.");
  }
  const releaseSlot = mode === "previous" ? "previous" : "current";
  const releaseId = releaseSlot === "previous" ? "2026.08.22.1" : "2026.08.22.2";
  const base = releaseBuild
    ? "./"
    : command === "serve"
      ? "http://127.0.0.1:4174/"
      : `http://127.0.0.1:4174/releases/${releaseSlot}/`;

  return {
    base,
    define: {
      __CADENCE_REMOTE_RELEASE__: JSON.stringify(
        command === "serve" ? "development" : releaseBuild ? "release" : releaseId,
      ),
    },
    server: {
      host: "127.0.0.1",
      port: 4174,
      strictPort: true,
      cors: true,
      origin: "http://127.0.0.1:4174",
    },
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? `dist/${releaseSlot}`,
      ...(releaseBuild
        ? {
            emptyOutDir: true,
            manifest: false,
            rollupOptions: { input: federatedEntry },
          }
        : {}),
    },
    test: {
      environment: "happy-dom",
    },
    plugins: lazyPlugins(() => [
      vue(),
      federation(
        releaseBuild
          ? { ...releaseFederationConfig, publicPath: "auto" }
          : federationConfig,
      ),
      ...(releaseBuild ? [releaseOutputPlugin()] : []),
    ]),
  };
});
