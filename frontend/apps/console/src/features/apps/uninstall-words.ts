import { plural } from "@/ui";

/**
 * Uninstall confirm (#679): the lines say who it stops for, and that the configuration stays. The
 * second line is true because uninstalling only ends the installation: the stored configuration is
 * kept and a later install picks it up (application_installations_test.exs, "retains
 * configuration across disable, uninstall, and reinstall transitions").
 */
export type UninstallScope = Readonly<
  { kind: "mission"; missionName: string; spacecraftCount: number } | { kind: "spacecraft" }
>;

export function uninstallLines(scope: UninstallScope): readonly string[] {
  const stops =
    scope.kind === "spacecraft"
      ? "It stops on this spacecraft."
      : scope.spacecraftCount === 0
        ? `There are no spacecraft in ${scope.missionName} yet, so nothing stops.`
        : `It stops on ${plural(scope.spacecraftCount, "spacecraft", "spacecraft")} in ${scope.missionName}.`;
  return [stops, "Its configuration is kept."];
}

export const uninstallTitle = (appName: string) => `Uninstall ${appName}?`;
export const uninstallVerb = (appName: string) => `Uninstall ${appName}`;
