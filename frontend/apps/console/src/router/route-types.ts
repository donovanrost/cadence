import type { RouteRecordInfo } from "vue-router";

/** Shared pieces of the typed route map (route-map.ts): raw/normalized params and record shapes. */
export type Raw = string | number;
export type RawOpt = string | number | null | undefined;

export type OrgRaw = { org?: Raw | undefined };
export type OrgParams = { org: string };
export type MissionRaw = OrgRaw & { mission?: Raw | undefined };
export type MissionParams = OrgParams & { mission: string };

/** The Investigate tabs (ops.spacecraft's `:tab`, the regex in ops-routes.ts). */
export const spacecraftTabs = [
  "investigate",
  "telemetry",
  "uplink",
  "passes",
  "configuration",
  "history",
] as const;
export type SpacecraftTab = (typeof spacecraftTabs)[number];
export const addSpacecraftSteps = ["source", "identity", "orbit", "review"] as const;
export type AddSpacecraftStep = (typeof addSpacecraftSteps)[number];

export type Plain<N extends string, P extends string> = RouteRecordInfo<
  N,
  P,
  Record<never, never>,
  Record<never, never>
>;
export type InOrg<N extends string, P extends string, R = object, Q = object> = RouteRecordInfo<
  N,
  `/:org${P}`,
  OrgRaw & R,
  OrgParams & Q
>;
export type InMission<N extends string, P extends string, R = object, Q = object> = RouteRecordInfo<
  N,
  `/:org/:mission${P}`,
  MissionRaw & R,
  MissionParams & Q
>;
