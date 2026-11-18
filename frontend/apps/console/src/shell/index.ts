export {
  canAdministerOrganization,
  hasCapability,
  organizationCapabilities,
  useSession,
} from "./session.ts";
export { useConsoleScope, useMissionScope, type ConsoleScope, type MissionScope } from "./scope.ts";
export { registerPalette, usePalette } from "./palette.ts";
export { default as TakeoverHeader } from "./TakeoverHeader.vue";
export { useMobileHeader, type MobileHeader } from "./mobile-header.ts";
export { useSmallScreen } from "./viewport.ts";
export { useDisclosure } from "./disclosure.ts";
/** Cockpit pieces for takeover headers (dashboards, DECISIONS #76): the UTC clocks and mission counts. */
export { default as ClockCluster } from "./ClockCluster.vue";
export { useOpsCounts, type OpsCounts } from "./counts.ts";
/** The mission runtime status from the shell's /counts read (U38; Setup CONVERGING / DEGRADED). */
export { useRuntimeStatus } from "./runtime-status.ts";
export { useFleetPosture } from "./fleet-posture.ts";
export { TopBarLevel, useTopBarLevel } from "./topbar-fit.ts";
export { outageText } from "./runtime-banner.ts";
export type { FleetPostureCounts, RuntimeStatus } from "./counts.ts";
/** L6 admin mode for features (L7 admin pages): state, enter/leave, and the step-up form. */
export { enterAdminMode, leaveAdminMode, useAdminMode } from "./admin-mode.ts";
export { default as AdminModeForm } from "./AdminModeForm.vue";
/** U89: the ADMIN MODE tag after an actor who decided in platform admin mode. */
export { default as AdminModeTag } from "./AdminModeTag.vue";
export { paramText } from "./route-params.ts";
/** Typed route names and the Investigate tab union (router/route-map.ts, typing audit Fix 4). */
export {
  isConsoleRouteName,
  isParamlessRouteName,
  linkByName,
  spacecraftTabs,
  type ConsoleRouteName,
  type ParamlessRouteName,
  type SpacecraftTab,
} from "@/router/route-map.ts";
