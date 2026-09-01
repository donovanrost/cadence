import { existsSync, realpathSync } from "node:fs";
import { federation } from "@module-federation/vite";
import vue from "@vitejs/plugin-vue";
import { isAbsolute, relative, resolve, sep } from "node:path";
import { defineConfig, lazyPlugins } from "vite-plus";
import federationConfig from "./module-federation.config";

const cadenceVueSource = resolve(__dirname, "../../../apps/cadence_web/assets/vue");
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
  if (!configuredOutput || configuredOutput.startsWith("-") || !isAbsolute(configuredOutput)) {
    throw new Error(
      `${releaseOutputEnvironmentName} must be an absolute output directory outside the repository.`,
    );
  }

  const argumentIndex = process.argv.findIndex(
    (argument) => argument === "--outDir" || argument.startsWith("--outDir="),
  );
  if (argumentIndex === -1) {
    throw new Error("Release builds require an absolute --outDir outside the repository.");
  }

  const argument = process.argv[argumentIndex];
  const value = argument?.startsWith("--outDir=")
    ? argument.slice("--outDir=".length)
    : process.argv[argumentIndex + 1];

  if (!value || value.startsWith("-") || !isAbsolute(value)) {
    throw new Error("Release builds require an absolute --outDir outside the repository.");
  }

  const outputDirectory = canonicalPathWithMissingTail(configuredOutput);
  const argumentOutputDirectory = canonicalPathWithMissingTail(value);
  if (outputDirectory !== argumentOutputDirectory) {
    throw new Error(`${releaseOutputEnvironmentName} must match --outDir.`);
  }

  const repositoryRelative = relative(repositoryRoot, outputDirectory);
  if (
    repositoryRelative === "" ||
    (!repositoryRelative.startsWith(`..${sep}`) &&
      repositoryRelative !== ".." &&
      !isAbsolute(repositoryRelative))
  ) {
    throw new Error("Release build output must be outside the repository.");
  }

  return outputDirectory;
}

function canonicalPathWithMissingTail(path: string) {
  const missingTail = [];
  let current = resolve(path);

  while (!existsSync(current)) {
    const parent = resolve(current, "..");
    if (parent === current) throw new Error("Release build output cannot be resolved.");
    missingTail.push(relative(parent, current));
    current = parent;
  }

  return resolve(realpathSync(current), ...missingTail.reverse());
}

export default defineConfig(({ mode }) => {
  const releaseBuild = mode === "release";
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
    },
    test: {
      environment: "happy-dom",
    },
    plugins: lazyPlugins(() => [vue(), federation(federationConfig)]),
  };
});
