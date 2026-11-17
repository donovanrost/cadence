import { spacecraftIdParam } from "@/api/ids.ts";
import { paramText } from "@/shell/route-params.ts";
import type { RouteRecordRaw } from "vue-router";

/** Setup mode, children of /console/:org/:mission. Owner: fe-setup (swap `pending` for your screen). */
export const setupMissionRoutes: RouteRecordRaw[] = [
  {
    path: "setup",
    name: "setup.readiness",
    component: () => import("@/features/readiness/ReadinessScreen.vue"),
    meta: { mode: "setup", nav: "readiness", title: "Readiness", board: "Setup (S1)" },
  },
  {
    path: "setup/spacecraft",
    name: "setup.spacecraft",
    component: () => import("@/features/spacecraft/SpacecraftListScreen.vue"),
    meta: { mode: "setup", nav: "spacecraft", title: "Spacecraft" },
  },
  {
    path: "setup/spacecraft/new/:step(source|identity|orbit|review)?",
    name: "setup.spacecraft.new",
    component: () => import("@/features/spacecraft/add/AddSpacecraftScreen.vue"),
    meta: {
      mode: "takeover",
      nav: "spacecraft",
      title: "Add spacecraft",
      board: "AddSpacecraft (S2)",
    },
  },
  {
    path: "setup/spacecraft/:spacecraftId",
    name: "setup.spacecraft.one",
    component: () => import("@/features/spacecraft/SpacecraftDetailScreen.vue"),
    meta: { mode: "setup", nav: "spacecraft", title: "Spacecraft" },
  },
  {
    // (B) ux U94: the craft's configuration workspace (ported from the host's spacecraft page).
    path: "setup/spacecraft/:spacecraftId/configuration/:section(overview|catalog|communications|changes)?",
    name: "setup.spacecraft.configuration",
    component: () => import("@/features/spacecraft/configuration/ConfigurationScreen.vue"),
    props: (to) => ({ spacecraftId: spacecraftIdParam(paramText(to.params, "spacecraftId")) }),
    meta: { mode: "setup", nav: "spacecraft", title: "Configuration" },
  },
  {
    // L19 (ux AppSurfaces.md; plans/spacecraft-apps.md): a spacecraft-scope app in the L9 host frame.
    path: "setup/spacecraft/:spacecraftId/apps/:appKey/:surface?",
    name: "setup.spacecraft.app",
    component: () => import("@/features/apps/AppSurfaceScreen.vue"),
    props: (to) => ({ spacecraftId: spacecraftIdParam(paramText(to.params, "spacecraftId")) }),
    meta: { mode: "setup", nav: "spacecraft", title: "App" },
  },
  {
    path: "setup/profiles",
    name: "setup.profiles",
    component: () => import("@/features/profiles/ProfilesListScreen.vue"),
    meta: { mode: "setup", nav: "profiles", title: "Profiles" },
  },
  {
    path: "setup/profiles/new",
    name: "setup.profile.new",
    component: () => import("@/features/profiles/ProfileNewScreen.vue"),
    meta: { mode: "setup", nav: "profiles", title: "New profile", board: "Profile (S4)" },
  },
  {
    path: "setup/profiles/:profileId/:section?",
    name: "setup.profile",
    component: () => import("@/features/profiles/ProfileScreen.vue"),
    meta: { mode: "setup", nav: "profiles", title: "Profile", board: "Profile (S4)" },
  },
  {
    path: "setup/catalog",
    name: "setup.catalog",
    component: () => import("@/features/catalog/CatalogScreen.vue"),
    meta: { mode: "setup", nav: "catalog", title: "Catalog" },
  },
  {
    path: "setup/catalog/import/:importId?",
    name: "setup.catalog.import",
    component: () => import("@/features/catalog/ImportScreen.vue"),
    meta: { mode: "setup", nav: "catalog", title: "Import catalog", board: "Catalog (S3)" },
  },
  {
    path: "setup/catalog/artifacts/:artifactId",
    name: "setup.catalog.artifact",
    component: () => import("@/features/catalog/ArtifactScreen.vue"),
    props: (to) => ({ artifactId: paramText(to.params, "artifactId") }),
    meta: { mode: "setup", nav: "catalog", title: "Source file" },
  },
  {
    // ux U65: a catalog revision's approval, by its mission model revision (api's wire).
    path: "setup/catalog/models/:revisionId",
    name: "setup.catalog.model",
    component: () => import("@/features/catalog/approval/ModelRevisionScreen.vue"),
    props: (to) => ({ revisionId: paramText(to.params, "revisionId") }),
    meta: { mode: "setup", nav: "catalog", title: "Catalog revision" },
  },
  {
    // ux §7 #8: one Catalog page with a database picker; the old path opens it on that database.
    path: "setup/catalog/:databaseId",
    name: "setup.catalog.database",
    redirect: (to) => ({
      name: "setup.catalog",
      query: { database: paramText(to.params, "databaseId") },
    }),
  },
  {
    path: "setup/changes",
    name: "setup.changes",
    component: () => import("@/features/changes/ChangesScreen.vue"),
    meta: { mode: "setup", nav: "readiness", title: "Staged changes" },
  },
  {
    path: "setup/changes/activations/:requestId",
    name: "setup.activation",
    component: () => import("@/features/activations/ActivationScreen.vue"),
    props: (to) => ({ requestId: paramText(to.params, "requestId") }),
    meta: { mode: "setup", nav: "readiness", title: "Activation" },
  },
  {
    path: "setup/revisions",
    name: "setup.revisions",
    component: () => import("@/features/changes/RevisionsScreen.vue"),
    meta: { mode: "setup", nav: "readiness", title: "Revisions" },
  },
  {
    // Changes.md §4: `revisions/r4...r6`.
    path: "setup/revisions/r:from(\\d+)...r:to(\\d+)",
    name: "setup.revisions.compare",
    component: () => import("@/features/changes/CompareScreen.vue"),
    meta: { mode: "setup", nav: "readiness", title: "Compare revisions" },
  },
  {
    path: "setup/revisions/:revision(\\d+)",
    name: "setup.revision",
    component: () => import("@/features/changes/RevisionScreen.vue"),
    meta: { mode: "setup", nav: "readiness", title: "Revision" },
  },
  {
    path: "setup/comms",
    name: "setup.comms",
    component: () => import("@/features/comms/CommsScreen.vue"),
    meta: { mode: "setup", nav: "comms", title: "Comms & routing" },
  },
  {
    path: "setup/comms/transports/:transportId?",
    name: "setup.comms.transports",
    component: () => import("@/features/comms/CommsScreen.vue"),
    meta: { mode: "setup", nav: "comms", title: "Transports" },
  },
  {
    path: "setup/stations/:stationId?",
    name: "setup.stations",
    component: () => import("@/features/stations/StationsScreen.vue"),
    meta: { mode: "setup", nav: "stations", title: "Ground stations" },
  },
  {
    path: "setup/stations/providers/:providerId?",
    name: "setup.stations.providers",
    component: () => import("@/features/stations/StationsScreen.vue"),
    meta: { mode: "setup", nav: "stations", title: "Providers" },
  },
  {
    path: "setup/contact-planning",
    name: "setup.contact-planning",
    component: () => import("@/features/planning/ContactPlanningScreen.vue"),
    meta: { mode: "setup", nav: "contact-planning", title: "Contact planning" },
  },
  {
    path: "setup/contact-planning/policy",
    name: "setup.contact-planning.policy",
    component: () => import("@/features/planning/ContactPlanningScreen.vue"),
    meta: { mode: "setup", nav: "contact-planning", title: "Contact planning policy" },
  },
  {
    path: "setup/contact-planning/requirements/:requirementId",
    name: "setup.contact-planning.requirement",
    component: () => import("@/features/planning/RequirementScreen.vue"),
    meta: { mode: "setup", nav: "contact-planning", title: "Contact requirement" },
  },
  {
    path: "setup/contact-planning/templates/:templateId",
    name: "setup.contact-planning.template",
    component: () => import("@/features/planning/TemplateScreen.vue"),
    meta: { mode: "setup", nav: "contact-planning", title: "Contact requirement template" },
  },
  {
    path: "setup/data-sources/:sourceId?",
    name: "setup.data-sources",
    component: () => import("@/features/sources/SourcesScreen.vue"),
    meta: { mode: "setup", nav: "data-sources", title: "Data sources" },
  },
  {
    path: "setup/apps",
    name: "setup.apps",
    component: () => import("@/features/apps/AppsScreen.vue"),
    meta: { mode: "setup", nav: "apps", title: "Apps" },
  },
  {
    // L9 (ux screens/AppSurfaces.md): the app's surface in the console host; no :surface opens its first.
    path: "setup/apps/:appKey/:surface?",
    name: "setup.app",
    component: () => import("@/features/apps/AppSurfaceScreen.vue"),
    meta: { mode: "setup", nav: "apps", title: "App" },
  },
  {
    path: "setup/settings/:section?",
    name: "setup.settings",
    component: () => import("@/features/settings/SettingsScreen.vue"),
    meta: { mode: "setup", nav: "mission-settings", title: "Mission settings" },
  },
];

/** Organization group, children of /console/:org. Owner: fe-setup. */
export const setupOrgRoutes: RouteRecordRaw[] = [
  {
    path: "org/people",
    name: "org.people",
    component: () => import("@/features/people/PeopleScreen.vue"),
    meta: { mode: "setup", nav: "people", title: "People & access", board: "People (S5)" },
  },
  {
    // ux §7 #8: the invite form lives on People (U2); this path focuses its email field.
    path: "org/people/invite",
    name: "org.people.invite",
    redirect: (to) => ({ name: "org.people", params: to.params, query: { invite: "1" } }),
  },
  {
    path: "org/people/services",
    name: "org.people.services",
    redirect: (to) => ({ name: "org.people", params: to.params, query: { tab: "services" } }),
  },
  {
    path: "org/people/services/new",
    name: "org.people.services.new",
    component: () => import("@/features/people/ServiceIdentityNewScreen.vue"),
    meta: { mode: "setup", nav: "people", title: "New service identity" },
  },
  {
    path: "org/people/services/:serviceId",
    name: "org.people.service",
    component: () => import("@/features/people/ServiceIdentityScreen.vue"),
    meta: { mode: "setup", nav: "people", title: "Service identity" },
  },
  {
    path: "org/people/:userId",
    name: "org.people.person",
    component: () => import("@/features/people/PersonScreen.vue"),
    meta: { mode: "setup", nav: "people", title: "Person" },
  },
  {
    path: "org/people/invitations/:invitationId",
    name: "org.people.invitation",
    component: () => import("@/features/people/InvitationScreen.vue"),
    meta: { mode: "setup", nav: "people", title: "Invitation" },
  },
  {
    path: "org/missions",
    name: "org.missions",
    component: () => import("@/features/missions/MissionsScreen.vue"),
    meta: { mode: "setup", nav: "missions", title: "Missions" },
  },
  {
    path: "org/missions/new",
    name: "org.missions.new",
    component: () => import("@/features/missions/MissionNewScreen.vue"),
    meta: { mode: "setup", nav: "missions", title: "New mission" },
  },
  {
    path: "org/provider-accounts/:accountId?",
    name: "org.provider-accounts",
    component: () => import("@/features/providers/ProviderAccountsScreen.vue"),
    meta: { mode: "setup", nav: "provider-accounts", title: "Provider accounts" },
  },
  {
    path: "org/settings/:section?",
    name: "org.settings",
    component: () => import("@/features/settings/SettingsScreen.vue"),
    meta: { mode: "setup", nav: "org-settings", title: "Organization settings" },
  },
  {
    path: "org/audit",
    name: "org.audit",
    component: () => import("@/features/audit/AuditScreen.vue"),
    meta: { mode: "setup", nav: "audit", title: "Audit log" },
  },
];
