import { isAbsolute, resolve } from "node:path";
import {
  assertOutputOutsideRepository,
  canonicalPathWithMissingTail,
  parseOutputDirectoryArgument,
} from "./frontend-release-paths.mjs";

const repositoryRoot = canonicalPathWithMissingTail(resolve(import.meta.dirname, "../.."));
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

/**
 * Read-only preflight shared by all release builds. Publication mode has its own fixed paths.
 * @param {{command: string, mode: string}} context
 * @param {{environment?: NodeJS.ProcessEnv, argumentsList?: string[]}} [options]
 */
export function releaseBuildOutput(
  { command, mode },
  { environment = process.env, argumentsList = process.argv.slice(2) } = {},
) {
  if (mode !== "release") return undefined;
  try {
    if (command !== "build") throw new Error("Release mode requires the Vite build command.");
    if (identityEnvironmentNames.some((name) => Object.hasOwn(environment, name)))
      throw new Error("Release builds do not accept release-identity environment injection.");
    const configured = environment[outputEnvironmentName];
    if (!configured || !isAbsolute(configured))
      throw new Error(
        `${outputEnvironmentName} must be an absolute output directory outside the repository.`,
      );
    const output = canonicalPathWithMissingTail(configured);
    const argument = canonicalPathWithMissingTail(parseOutputDirectoryArgument(argumentsList));
    if (output !== argument) throw new Error(`${outputEnvironmentName} must match --outDir.`);
    assertOutputOutsideRepository(output, repositoryRoot);
    return output;
  } catch (cause) {
    throw new Error(
      `Release build output is invalid: ${cause instanceof Error ? cause.message : "unavailable output path"}`,
      { cause },
    );
  }
}

/** @param {string} output */
export function releaseOutputGuard(output) {
  return {
    name: "cadence-release-output-preflight",
    // Vite resolves CLI overrides before this hook and prepares output directories afterward.
    /** @param {{root: string, build: {outDir: string}}} config */
    configResolved(config) {
      const effective = canonicalPathWithMissingTail(resolve(config.root, config.build.outDir));
      assertOutputOutsideRepository(effective, repositoryRoot);
      if (effective !== output)
        throw new Error("Release build output changed after --outDir admission.");
    },
  };
}
