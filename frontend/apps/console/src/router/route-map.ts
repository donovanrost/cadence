import type { RouteLocationRaw, RouteRecordInfo } from "vue-router";
import type { Scid } from "@/api/ids.ts";

/**
 * Typed route names and params (typing audit Fix 4, BACKLOG §12 A3). Every route the console
 * registers has an entry; `route-map.test.ts` checks both directions against the router.
 *
 * Raw params (what links pass) leave `org` and `mission` optional: a named link inside a mission
 * reuses the current route's `org`/`mission`, as vue-router does at runtime. Normalized params
 * (what `useRoute(name).params` reads) have them. Optional segments read as "" when absent.
 */
type Raw = string | number;
type RawOpt = string | number | null | undefined;

type OrgRaw = { org?: Raw | undefined };
type OrgParams = { org: string };
type MissionRaw = OrgRaw & { mission?: Raw | undefined };
type MissionParams = OrgParams & { mission: string };

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

type Plain<N extends string, P extends string> = RouteRecordInfo<
  N,
  P,
  Record<never, never>,
  Record<never, never>
>;
type InOrg<N extends string, P extends string, R = object, Q = object> = RouteRecordInfo<
  N,
  `/:org${P}`,
  OrgRaw & R,
  OrgParams & Q
>;
type InMission<N extends string, P extends string, R = object, Q = object> = RouteRecordInfo<
  N,
  `/:org/:mission${P}`,
  MissionRaw & R,
  MissionParams & Q
>;

export interface ConsoleRoutes {
  home: Plain<"home", "/">;
  "auth.sign-in": Plain<"auth.sign-in", "/sign-in">;
  "auth.invitation": RouteRecordInfo<
    "auth.invitation",
    "/invitations/:token",
    { token: Raw },
    { token: string }
  >;
  "auth.no-org": Plain<"auth.no-org", "/no-organization">;
  account: Plain<"account", "/account">;
  kit: Plain<"kit", "/kit">;
  admin: Plain<"admin", "/admin">;
  "admin.organizations": Plain<"admin.organizations", "/admin/organizations">;
  "admin.organization": RouteRecordInfo<
    "admin.organization",
    "/admin/organizations/:orgId",
    { orgId: Raw },
    { orgId: string }
  >;
  "admin.service-identities": Plain<"admin.service-identities", "/admin/service-identities">;
  "admin.runtime": Plain<"admin.runtime", "/admin/runtime">;
  "admin.audit": Plain<"admin.audit", "/admin/audit">;
  "not-found": RouteRecordInfo<
    "not-found",
    "/:pathMatch(.*)*",
    { pathMatch: Raw[] },
    { pathMatch: string[] }
  >;

  "org.home": InOrg<"org.home", "">;
  "org.people": InOrg<"org.people", "/org/people">;
  "org.people.invite": InOrg<"org.people.invite", "/org/people/invite">;
  "org.people.services": InOrg<"org.people.services", "/org/people/services">;
  "org.people.services.new": InOrg<"org.people.services.new", "/org/people/services/new">;
  "org.people.service": InOrg<
    "org.people.service",
    "/org/people/services/:serviceId",
    { serviceId: Raw },
    { serviceId: string }
  >;
  "org.people.person": InOrg<
    "org.people.person",
    "/org/people/:userId",
    { userId: Raw },
    { userId: string }
  >;
  "org.people.invitation": InOrg<
    "org.people.invitation",
    "/org/people/invitations/:invitationId",
    { invitationId: Raw },
    { invitationId: string }
  >;
  "org.missions": InOrg<"org.missions", "/org/missions">;
  "org.missions.new": InOrg<"org.missions.new", "/org/missions/new">;
  "org.provider-accounts": InOrg<
    "org.provider-accounts",
    "/org/provider-accounts/:accountId?",
    { accountId?: RawOpt },
    { accountId?: string }
  >;
  "org.settings": InOrg<
    "org.settings",
    "/org/settings/:section?",
    { section?: RawOpt },
    { section?: string }
  >;
  "org.audit": InOrg<"org.audit", "/org/audit">;

  "mission.home": InMission<"mission.home", "">;
  "ops.now": InMission<"ops.now", "/now">;
  "ops.fleet": InMission<"ops.fleet", "/fleet">;
  "ops.spacecraft": InMission<
    "ops.spacecraft",
    "/fleet/:scId(\\d+)/:tab?",
    // The SCID, a number (scidParam reads it back); never the spacecraft id (§12C, audit §1.2).
    { scId: Scid; tab?: SpacecraftTab | null | undefined },
    { scId: string; tab?: SpacecraftTab | "" }
  >;
  "ops.alarms": InMission<"ops.alarms", "/alarms">;
  "ops.commands": InMission<"ops.commands", "/commands">;
  "ops.commands.new": InMission<"ops.commands.new", "/commands/new">;
  "ops.commands.request": InMission<
    "ops.commands.request",
    "/commands/:requestId/:view?",
    { requestId: Raw; view?: "review" | "uplink" | null | undefined },
    { requestId: string; view?: "review" | "uplink" | "" }
  >;
  "ops.contacts": InMission<"ops.contacts", "/contacts">;
  "ops.contacts.plan": InMission<"ops.contacts.plan", "/contacts/plan">;
  "ops.contacts.replan.station": InMission<
    "ops.contacts.replan.station",
    "/contacts/replan/:stationId",
    { stationId: Raw },
    { stationId: string }
  >;
  "ops.contacts.replan": InMission<"ops.contacts.replan", "/contacts/replan">;
  "ops.contacts.review": InMission<"ops.contacts.review", "/contacts/review">;
  "ops.contacts.history": InMission<"ops.contacts.history", "/contacts/history">;
  "ops.contact": InMission<
    "ops.contact",
    "/contacts/:contactId",
    { contactId: Raw },
    { contactId: string }
  >;
  "ops.telemetry": InMission<"ops.telemetry", "/telemetry">;
  "ops.dashboards": InMission<"ops.dashboards", "/telemetry/dashboards">;
  "ops.dashboards.new": InMission<"ops.dashboards.new", "/telemetry/dashboards/new">;
  "ops.dashboards.library": InMission<"ops.dashboards.library", "/telemetry/dashboards/library">;
  "ops.dashboards.library.item": InMission<
    "ops.dashboards.library.item",
    "/telemetry/dashboards/library/:itemId",
    { itemId: Raw },
    { itemId: string }
  >;
  "ops.dashboards.playlists": InMission<
    "ops.dashboards.playlists",
    "/telemetry/dashboards/playlists"
  >;
  "ops.dashboards.present": InMission<
    "ops.dashboards.present",
    "/telemetry/dashboards/playlists/:playlistId/present",
    { playlistId: Raw },
    { playlistId: string }
  >;
  "ops.dashboards.share": InMission<
    "ops.dashboards.share",
    "/telemetry/dashboards/shares/:shareId",
    { shareId: Raw },
    { shareId: string }
  >;
  "ops.dashboards.snapshot": InMission<
    "ops.dashboards.snapshot",
    "/telemetry/dashboards/snapshots/:snapshotId",
    { snapshotId: Raw },
    { snapshotId: string }
  >;
  "ops.dashboard": InMission<
    "ops.dashboard",
    "/telemetry/dashboards/:dashboardId",
    { dashboardId: Raw },
    { dashboardId: string }
  >;
  "ops.dashboard.edit": InMission<
    "ops.dashboard.edit",
    "/telemetry/dashboards/:dashboardId/edit",
    { dashboardId: Raw },
    { dashboardId: string }
  >;
  "ops.dashboard.settings": InMission<
    "ops.dashboard.settings",
    "/telemetry/dashboards/:dashboardId/settings/:tab?",
    { dashboardId: Raw; tab?: RawOpt },
    { dashboardId: string; tab?: string }
  >;
  "ops.timeline": InMission<"ops.timeline", "/timeline">;

  "setup.readiness": InMission<"setup.readiness", "/setup">;
  "setup.spacecraft": InMission<"setup.spacecraft", "/setup/spacecraft">;
  "setup.spacecraft.new": InMission<
    "setup.spacecraft.new",
    "/setup/spacecraft/new/:step?",
    { step?: AddSpacecraftStep | null | undefined },
    { step?: AddSpacecraftStep | "" }
  >;
  "setup.spacecraft.one": InMission<
    "setup.spacecraft.one",
    "/setup/spacecraft/:spacecraftId",
    { spacecraftId: Raw },
    { spacecraftId: string }
  >;
  "setup.spacecraft.app": InMission<
    "setup.spacecraft.app",
    "/setup/spacecraft/:spacecraftId/apps/:appKey/:surface?",
    { spacecraftId: Raw; appKey: Raw; surface?: RawOpt },
    { spacecraftId: string; appKey: string; surface?: string }
  >;
  "setup.profiles": InMission<"setup.profiles", "/setup/profiles">;
  "setup.profile.new": InMission<"setup.profile.new", "/setup/profiles/new">;
  "setup.profile": InMission<
    "setup.profile",
    "/setup/profiles/:profileId/:section?",
    { profileId: Raw; section?: RawOpt },
    { profileId: string; section?: string }
  >;
  "setup.catalog": InMission<"setup.catalog", "/setup/catalog">;
  "setup.catalog.artifact": InMission<
    "setup.catalog.artifact",
    "/setup/catalog/artifacts/:artifactId",
    { artifactId: Raw },
    { artifactId: string }
  >;
  "setup.catalog.import": InMission<
    "setup.catalog.import",
    "/setup/catalog/import/:importId?",
    { importId?: RawOpt },
    { importId?: string }
  >;
  "setup.catalog.model": InMission<
    "setup.catalog.model",
    "/setup/catalog/models/:revisionId",
    { revisionId: Raw },
    { revisionId: string }
  >;
  "setup.catalog.database": InMission<
    "setup.catalog.database",
    "/setup/catalog/:databaseId",
    { databaseId: Raw },
    { databaseId: string }
  >;
  "setup.changes": InMission<"setup.changes", "/setup/changes">;
  "setup.activation": InMission<
    "setup.activation",
    "/setup/changes/activations/:requestId",
    { requestId: Raw },
    { requestId: string }
  >;
  "setup.revisions": InMission<"setup.revisions", "/setup/revisions">;
  "setup.revisions.compare": InMission<
    "setup.revisions.compare",
    "/setup/revisions/r:from(\\d+)...r:to(\\d+)",
    { from: Raw; to: Raw },
    { from: string; to: string }
  >;
  "setup.revision": InMission<
    "setup.revision",
    "/setup/revisions/:revision(\\d+)",
    { revision: Raw },
    { revision: string }
  >;
  "setup.comms": InMission<"setup.comms", "/setup/comms">;
  "setup.comms.transports": InMission<
    "setup.comms.transports",
    "/setup/comms/transports/:transportId?",
    { transportId?: RawOpt },
    { transportId?: string }
  >;
  "setup.stations": InMission<
    "setup.stations",
    "/setup/stations/:stationId?",
    { stationId?: RawOpt },
    { stationId?: string }
  >;
  "setup.stations.providers": InMission<
    "setup.stations.providers",
    "/setup/stations/providers/:providerId?",
    { providerId?: RawOpt },
    { providerId?: string }
  >;
  "setup.contact-planning": InMission<"setup.contact-planning", "/setup/contact-planning">;
  "setup.contact-planning.policy": InMission<
    "setup.contact-planning.policy",
    "/setup/contact-planning/policy"
  >;
  "setup.contact-planning.requirement": InMission<
    "setup.contact-planning.requirement",
    "/setup/contact-planning/requirements/:requirementId",
    { requirementId: Raw },
    { requirementId: string }
  >;
  "setup.contact-planning.template": InMission<
    "setup.contact-planning.template",
    "/setup/contact-planning/templates/:templateId",
    { templateId: Raw },
    { templateId: string }
  >;
  "setup.data-sources": InMission<
    "setup.data-sources",
    "/setup/data-sources/:sourceId?",
    { sourceId?: RawOpt },
    { sourceId?: string }
  >;
  "setup.apps": InMission<"setup.apps", "/setup/apps">;
  "setup.app": InMission<
    "setup.app",
    "/setup/apps/:appKey/:surface?",
    { appKey: Raw; surface?: RawOpt },
    { appKey: string; surface?: string }
  >;
  "setup.settings": InMission<
    "setup.settings",
    "/setup/settings/:section?",
    { section?: RawOpt },
    { section?: string }
  >;
}

export type ConsoleRouteName = keyof ConsoleRoutes;

/** Every name, once (compile-checked exhaustive), for the router sync test. */
export const consoleRouteNames: Readonly<Record<ConsoleRouteName, true>> = {
  home: true,
  "auth.sign-in": true,
  "auth.invitation": true,
  "auth.no-org": true,
  account: true,
  kit: true,
  admin: true,
  "admin.organizations": true,
  "admin.organization": true,
  "admin.service-identities": true,
  "admin.runtime": true,
  "admin.audit": true,
  "not-found": true,
  "org.home": true,
  "org.people": true,
  "org.people.invite": true,
  "org.people.services": true,
  "org.people.services.new": true,
  "org.people.service": true,
  "org.people.person": true,
  "org.people.invitation": true,
  "org.missions": true,
  "org.missions.new": true,
  "org.provider-accounts": true,
  "org.settings": true,
  "org.audit": true,
  "mission.home": true,
  "ops.now": true,
  "ops.fleet": true,
  "ops.spacecraft": true,
  "ops.alarms": true,
  "ops.commands": true,
  "ops.commands.new": true,
  "ops.commands.request": true,
  "ops.contacts": true,
  "ops.contacts.plan": true,
  "ops.contacts.replan.station": true,
  "ops.contacts.replan": true,
  "ops.contacts.review": true,
  "ops.contacts.history": true,
  "ops.contact": true,
  "ops.telemetry": true,
  "ops.dashboards": true,
  "ops.dashboards.new": true,
  "ops.dashboards.library": true,
  "ops.dashboards.library.item": true,
  "ops.dashboards.playlists": true,
  "ops.dashboards.present": true,
  "ops.dashboards.share": true,
  "ops.dashboards.snapshot": true,
  "ops.dashboard": true,
  "ops.dashboard.edit": true,
  "ops.dashboard.settings": true,
  "ops.timeline": true,
  "setup.readiness": true,
  "setup.spacecraft": true,
  "setup.spacecraft.new": true,
  "setup.spacecraft.one": true,
  "setup.spacecraft.app": true,
  "setup.profiles": true,
  "setup.profile.new": true,
  "setup.profile": true,
  "setup.catalog": true,
  "setup.catalog.import": true,
  "setup.catalog.database": true,
  "setup.catalog.model": true,
  "setup.catalog.artifact": true,
  "setup.changes": true,
  "setup.activation": true,
  "setup.revisions": true,
  "setup.revisions.compare": true,
  "setup.revision": true,
  "setup.comms": true,
  "setup.comms.transports": true,
  "setup.stations": true,
  "setup.stations.providers": true,
  "setup.contact-planning": true,
  "setup.contact-planning.policy": true,
  "setup.contact-planning.requirement": true,
  "setup.contact-planning.template": true,
  "setup.data-sources": true,
  "setup.apps": true,
  "setup.app": true,
  "setup.settings": true,
};

/** A name the console registers (e.g. from `router.getRoutes()`, whose names are untyped). */
export const isConsoleRouteName = (name: unknown): name is ConsoleRouteName =>
  typeof name === "string" && Object.hasOwn(consoleRouteNames, name);

/** Routes that take no params of their own (`org`/`mission` are inherited; optional ones may be left out). */
export type ParamlessRouteName = {
  [N in ConsoleRouteName]: Record<never, never> extends ConsoleRoutes[N]["paramsRaw"] ? N : never;
}[ConsoleRouteName];

/** Every paramless name, once (compile-checked against ParamlessRouteName both ways). */
const paramlessRouteNames: Readonly<Record<ParamlessRouteName, true>> = {
  home: true,
  "auth.sign-in": true,
  "auth.no-org": true,
  account: true,
  kit: true,
  admin: true,
  "admin.organizations": true,
  "admin.service-identities": true,
  "admin.runtime": true,
  "admin.audit": true,
  "org.home": true,
  "org.people": true,
  "org.people.invite": true,
  "org.people.services": true,
  "org.people.services.new": true,
  "org.missions": true,
  "org.missions.new": true,
  "org.provider-accounts": true,
  "org.settings": true,
  "org.audit": true,
  "mission.home": true,
  "ops.now": true,
  "ops.fleet": true,
  "ops.alarms": true,
  "ops.commands": true,
  "ops.commands.new": true,
  "ops.contacts": true,
  "ops.contacts.plan": true,
  "ops.contacts.replan": true,
  "ops.contacts.review": true,
  "ops.contacts.history": true,
  "ops.telemetry": true,
  "ops.dashboards": true,
  "ops.dashboards.new": true,
  "ops.dashboards.library": true,
  "ops.dashboards.playlists": true,
  "ops.timeline": true,
  "setup.readiness": true,
  "setup.spacecraft": true,
  "setup.spacecraft.new": true,
  "setup.profiles": true,
  "setup.profile.new": true,
  "setup.catalog": true,
  "setup.catalog.import": true,
  "setup.changes": true,
  "setup.revisions": true,
  "setup.comms": true,
  "setup.comms.transports": true,
  "setup.stations": true,
  "setup.stations.providers": true,
  "setup.contact-planning": true,
  "setup.contact-planning.policy": true,
  "setup.data-sources": true,
  "setup.apps": true,
  "setup.settings": true,
};

export const isParamlessRouteName = (name: unknown): name is ParamlessRouteName =>
  typeof name === "string" && Object.hasOwn(paramlessRouteNames, name);

/**
 * A link to a paramless route whose name is only known at run time (palette pages, chords, a
 * lookup table). TypeScript can't match `{ name: A | B }` against vue-router's per-name union, so
 * this is the one adapter that bridges it.
 */
export function linkByName(name: ParamlessRouteName): RouteLocationRaw {
  // oxlint-disable-next-line typescript/no-unsafe-type-assertion -- every member of ParamlessRouteName takes no required params, so `{ name }` is a valid location for each one.
  return { name } as RouteLocationRaw;
}
