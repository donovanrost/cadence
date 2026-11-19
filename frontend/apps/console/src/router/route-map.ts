import type { OpsRoutes } from "./route-map-ops.ts";
import type { OrgRoutes } from "./route-map-org.ts";
import type { SetupRoutes } from "./route-map-setup.ts";

/**
 * Typed route names and params (typing audit Fix 4, BACKLOG §12 A3). Every route the console
 * registers has an entry; `route-map.test.ts` checks both directions against the router.
 *
 * Raw params (what links pass) leave `org` and `mission` optional: a named link inside a mission
 * reuses the current route's `org`/`mission`, as vue-router does at runtime. Normalized params
 * (what `useRoute(name).params` reads) have them. Optional segments read as "" when absent.
 */
export interface ConsoleRoutes extends OrgRoutes, OpsRoutes, SetupRoutes {}

export type ConsoleRouteName = keyof ConsoleRoutes;

// The public entry: everything route-map.ts exported before its split (lead 11-16, 400-line rule).
export {
  addSpacecraftSteps,
  spacecraftTabs,
  type AddSpacecraftStep,
  type SpacecraftTab,
} from "./route-types.ts";
export {
  consoleRouteNames,
  isConsoleRouteName,
  isParamlessRouteName,
  linkByName,
  type ParamlessRouteName,
} from "./route-names.ts";
