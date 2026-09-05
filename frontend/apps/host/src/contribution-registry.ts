import { defineApplicationContribution, type ApplicationContribution } from "@cadence/plugin-sdk";

export interface ApplicationContributionRegistry<TModule = unknown> {
  register(contribution: ApplicationContribution<TModule>): ApplicationContribution<TModule>;
  get(
    applicationKey: string,
    applicationVersion?: number,
  ): ApplicationContribution<TModule> | undefined;
  list(): readonly ApplicationContribution<TModule>[];
}

/**
 * Keeps renderer contributions explicit and immutable within one host realm.
 * The Phoenix catalog remains the admission authority; this registry only
 * indexes already-approved remote modules for a renderer boundary.
 */
export function createApplicationContributionRegistry<TModule = unknown>(
  initial: readonly ApplicationContribution<TModule>[] = [],
): ApplicationContributionRegistry<TModule> {
  const contributions = new Map<string, ApplicationContribution<TModule>>();

  const register = (
    candidate: ApplicationContribution<TModule>,
  ): ApplicationContribution<TModule> => {
    const contribution = defineApplicationContribution(candidate);
    const identity = contributionIdentity(contribution);
    if (contributions.has(identity)) {
      throw new Error(`Application contribution ${identity} is already registered.`);
    }
    contributions.set(identity, contribution);
    return contribution;
  };

  for (const contribution of initial) register(contribution);

  return {
    register,
    get(applicationKey, applicationVersion) {
      const matches = [...contributions.values()].filter(
        ({ manifest }) =>
          manifest.application.applicationKey === applicationKey &&
          (applicationVersion === undefined || manifest.application.version === applicationVersion),
      );
      return matches.at(-1);
    },
    list() {
      return [...contributions.values()];
    },
  };
}

function contributionIdentity(contribution: ApplicationContribution): string {
  const { application, package: packageInfo } = contribution.manifest;
  return `${packageInfo.packageId}@${packageInfo.version}/${application.applicationKey}@${application.version}`;
}
