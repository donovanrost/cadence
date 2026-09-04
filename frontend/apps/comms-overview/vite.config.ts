import { createHash } from "node:crypto";
import { lstatSync, realpathSync, statSync } from "node:fs";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { basename, dirname, isAbsolute, posix, relative, resolve, sep } from "node:path";
import { defineConfig, lazyPlugins, type ViteUserConfig } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");
const federatedEntry = resolve(__dirname, "src/federated-application.ts");
const releaseFederationConfig = {
  ...federationConfig,
  hostInitInjectLocation: "entry" as const,
  manifest: {
    additionalData: ({ stats }: { stats: Record<string, unknown> }) => {
      if (!Object.hasOwn(stats, "assetAnalysis")) return stats;
      const publicationStats = { ...stats };
      delete publicationStats.assetAnalysis;
      return publicationStats;
    },
  },
};
const publicationRoot = resolve(
  __dirname,
  "../../../apps/cadence_web/priv/static/assets/application-host/comms-overview",
);
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

function releaseOutputDirectory() {
  const configuredOutput = process.env[releaseOutputEnvironmentName];
  if (!configuredOutput) {
    throw new Error(
      `${releaseOutputEnvironmentName} must be an absolute output directory outside the repository.`,
    );
  }
  if (!isAbsolute(configuredOutput)) {
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
  const missingTail = [];
  let current = resolve(path);

  while (true) {
    try {
      const canonicalExisting = realpathSync(current);
      if (missingTail.length > 0 && !statSync(canonicalExisting).isDirectory()) {
        throw new Error("Release build output has a non-directory parent.");
      }
      return resolve(canonicalExisting, ...missingTail.reverse());
    } catch {
      let existingEntry;
      try {
        existingEntry = lstatSync(current);
      } catch (error) {
        if (!(error && typeof error === "object" && "code" in error && error.code === "ENOENT")) {
          throw error;
        }
      }

      if (existingEntry) {
        throw new Error("Release build output cannot resolve a path component.");
      }

      const parent = dirname(current);
      if (parent === current) throw new Error("Release build output cannot be resolved.");
      missingTail.push(basename(current));
      current = parent;
    }
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

type ReleaseBundleItem = {
  code?: string;
  fileName?: string;
  facadeModuleId?: string;
  imports?: string[];
  dynamicImports?: string[];
  implicitlyLoadedBefore?: string[];
  referencedFiles?: string[];
  isEntry?: boolean;
  name?: string;
  source?: string | Uint8Array;
  type?: string;
};

const exactHostInitializationPath = /^assets\/hostInit-[A-Za-z0-9_-]{8}\.js$/;
const exactHostInitializationFacadeId =
  "\0virtual:mf:__mfe_internal__cadence_comms_overview__mf_owner__1__H_A_I__hostAutoInit__H_A_I__.js";
const exactHostInitializationFacadeIds = new Set([
  exactHostInitializationFacadeId,
  exactHostInitializationFacadeId.slice(1),
]);
const generatedHostInitializationSourceDigests = new Set([
  "e25074ccfca4c766e209adf9e7529680fcca051c844fa5d6d6c1a8e139601068",
]);

function canonicalHostInitializationSource(source: string) {
  if (typeof source !== "string" || /(?:^|[^\\])\/(?:\/|\*)/.test(source)) return null;
  const expectedRemoteName = federationConfig.name;
  const escapedRemoteName = expectedRemoteName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const expectedSharedImport = new RegExp(
    `_virtual_mf-localSharedImportMap___mfe_internal__${escapedRemoteName}__mf_owner__1-[A-Za-z0-9_-]{8}\\.js`,
  );
  if (!expectedSharedImport.test(source)) return null;
  return source
    .replace(/vite-preload-helper-[A-Za-z0-9_-]{8}\.js/g, "vite-preload-helper-<hash>.js")
    .replace(
      /_virtual_mf-localSharedImportMap___mfe_internal__[A-Za-z0-9._-]+__mf_owner__1-[A-Za-z0-9_-]{8}\.js/g,
      "_virtual_mf-localSharedImportMap___mfe_internal__<remote>__mf_owner__1-<hash>.js",
    )
    .replaceAll(expectedRemoteName, "<remote>")
    .replace(/\s+/g, "");
}

function hasHostInitializationShape(fileName: string, item: ReleaseBundleItem) {
  return (
    exactHostInitializationPath.test(fileName) &&
    item.type === "chunk" &&
    item.isEntry === false &&
    (item.name === "hostInit" || item.name === basename(fileName, ".js")) &&
    typeof item.code === "string" &&
    item.code.includes("__mf_module_cache__") &&
    item.code.includes("loadShare") &&
    /export\s*\{(?=[^}]*\bhostInitPromise\b)(?=[^}]*\binitHost\b)[^}]*\}/s.test(
      item.code,
    )
  );
}

function isAuthoritativeHostInitializationChunk(
  fileName: string,
  item: ReleaseBundleItem,
): item is ReleaseBundleItem & { code: string } {
  if (!hasHostInitializationShape(fileName, item)) return false;
  if (typeof item.code !== "string") return false;
  if (item.name !== "hostInit" || !exactHostInitializationFacadeIds.has(item.facadeModuleId ?? "")) {
    return false;
  }
  const canonical = canonicalHostInitializationSource(item.code);
  return (
    canonical !== null &&
    generatedHostInitializationSourceDigests.has(
      createHash("sha256").update(canonical, "utf8").digest("hex"),
    )
  );
}

function bundleReferenceMatches(owner: string, reference: string, target: string) {
  const normalized = reference.replaceAll("\\", "/");
  return [
    normalized,
    posix.normalize(posix.join(posix.dirname(owner), normalized)),
  ].includes(target);
}

function bundleItemReferencesTarget(
  owner: string,
  item: ReleaseBundleItem,
  target: string,
) {
  for (const field of [
    "imports",
    "dynamicImports",
    "implicitlyLoadedBefore",
    "referencedFiles",
  ] as const) {
    if (item[field]?.some((reference) => bundleReferenceMatches(owner, reference, target))) {
      return true;
    }
  }
  if (typeof item.code === "string") {
    const targetName = basename(target);
    return (
      item.code.includes(target) ||
      item.code.includes(`./${targetName}`) ||
      item.code.includes(`../${targetName}`)
    );
  }
  return false;
}

function releaseOutputPlugin() {
  return {
    name: "cadence-comms-overview-release-output",
    enforce: "post",
    apply: "build",
    config(config: ViteUserConfig) {
      config.build ??= {};
      config.build.manifest = false;
    },
    generateBundle(_options: unknown, bundle: Record<string, ReleaseBundleItem>) {
      const structuralHostInitializationLookalikes = Object.entries(bundle).filter(
        ([fileName, item]) => hasHostInitializationShape(fileName, item),
      );
      const authoritativeHostInitialization = Object.entries(bundle).filter(
        ([fileName, item]) => isAuthoritativeHostInitializationChunk(fileName, item),
      );
      if (authoritativeHostInitialization.length === 0) {
        throw new Error("release cleanup requires one authoritative host initialization chunk");
      }
      if (authoritativeHostInitialization.length > 1) {
        throw new Error("release cleanup found multiple authoritative host initialization chunks");
      }
      if (structuralHostInitializationLookalikes.length !== 1) {
        throw new Error(
          "release cleanup found conflicting structural host initialization lookalikes",
        );
      }

      const [[fileName, item]] = authoritativeHostInitialization;
      if (
        Object.entries(bundle).some(
          ([owner, ownerItem]) =>
            owner !== fileName && bundleItemReferencesTarget(owner, ownerItem, fileName),
        )
      ) {
        return;
      }

      const statsAsset = bundle["mf-stats.json"];
      if (statsAsset?.type !== "asset" || statsAsset.source === undefined) {
        throw new Error("release cleanup requires the federation stats asset");
      }
      const statsText =
        typeof statsAsset.source === "string"
          ? statsAsset.source
          : new TextDecoder().decode(statsAsset.source);
      const stats = JSON.parse(statsText) as {
        id?: string;
        name?: string;
        metaData?: {
          name?: string;
          remoteEntry?: { name?: string; path?: string; type?: string };
        };
        buildOutput?: Array<{
          fileName?: string;
          isEntry?: boolean;
          size?: number;
          type?: string;
        }>;
      };
      if (
        stats.id !== federationConfig.name ||
        stats.name !== federationConfig.name ||
        stats.metaData?.name !== federationConfig.name ||
        stats.metaData.remoteEntry?.name !== "remoteEntry.js" ||
        stats.metaData.remoteEntry.path !== "" ||
        stats.metaData.remoteEntry.type !== "module"
      ) {
        throw new Error("release cleanup requires authoritative federation stats provenance");
      }
      if (!Array.isArray(stats.buildOutput)) {
        throw new Error("release cleanup requires federation buildOutput records");
      }

      const matching = stats.buildOutput.filter((output) => output.fileName === fileName);
      if (matching.length !== 1) {
        throw new Error(`release cleanup requires one matching stats record for ${fileName}`);
      }
      const [record] = matching;
      if (
        record.type !== "chunk" ||
        record.isEntry !== false ||
        record.size !== new TextEncoder().encode(item.code).byteLength
      ) {
        throw new Error(`release cleanup found non-authoritative stats for ${fileName}`);
      }
      delete bundle[fileName];
      stats.buildOutput = stats.buildOutput.filter(
        (output) => output.fileName !== fileName,
      );
      statsAsset.source = JSON.stringify(stats);
    },
  };
}

export default defineConfig(({ command, mode }) => {
  const releaseBuild = mode === "release";
  if (releaseBuild && command !== "build") {
    throw new Error("Release mode requires the Vite build command.");
  }
  const outputDirectory = releaseBuild ? releaseOutputDirectory() : undefined;

  if (
    releaseBuild &&
    releaseIdentityEnvironmentNames.some((name) => Object.hasOwn(process.env, name))
  ) {
    throw new Error("Release builds do not accept release-identity environment injection.");
  }

  return {
    define: {
      "process.env.NODE_ENV": JSON.stringify("production"),
    },
    base: releaseBuild ? "./" : "/assets/application-host/comms-overview/",
    resolve: {
      alias: {
        "@cadence/cadence-web-vue": cadenceVueSource,
      },
    },
    server: {
      host: "127.0.0.1",
      port: 4176,
      strictPort: true,
      cors: true,
      origin: "http://127.0.0.1:4176",
    },
    preview: {
      host: "127.0.0.1",
      port: 4176,
      strictPort: true,
    },
    build: {
      target: "chrome89",
      outDir: outputDirectory ?? publicationRoot,
      emptyOutDir: true,
      ...(releaseBuild
        ? {
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
      federation(releaseBuild ? releaseFederationConfig : federationConfig),
      ...(releaseBuild ? [releaseOutputPlugin()] : []),
    ]),
  };
});
