import type { RouteRecordRaw } from "vue-router";
import { pending } from "./pending.ts";

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
    path: "setup/spacecraft/:scId",
    name: "setup.spacecraft.one",
    component: pending,
    meta: { mode: "setup", nav: "spacecraft", title: "Spacecraft" },
  },
  {
    path: "setup/profiles",
    name: "setup.profiles",
    component: () => import("@/features/profiles/ProfilesListScreen.vue"),
    meta: { mode: "setup", nav: "profiles", title: "Profiles" },
  },
  {
    path: "setup/profiles/:profileId/:section?",
    name: "setup.profile",
    component: pending,
    meta: { mode: "setup", nav: "profiles", title: "Profile", board: "Profile (S4)" },
  },
  {
    path: "setup/catalog",
    name: "setup.catalog",
    component: pending,
    meta: { mode: "setup", nav: "catalog", title: "Catalog" },
  },
  {
    path: "setup/catalog/import/:importId?",
    name: "setup.catalog.import",
    component: pending,
    meta: { mode: "setup", nav: "catalog", title: "Import catalog", board: "Catalog (S3)" },
  },
  {
    path: "setup/catalog/:databaseId",
    name: "setup.catalog.database",
    component: pending,
    meta: { mode: "setup", nav: "catalog", title: "Catalog" },
  },
  {
    path: "setup/comms",
    name: "setup.comms",
    component: pending,
    meta: { mode: "setup", nav: "comms", title: "Comms & routing" },
  },
  {
    path: "setup/comms/transports/:transportId?",
    name: "setup.comms.transports",
    component: pending,
    meta: { mode: "setup", nav: "comms", title: "Transports" },
  },
  {
    path: "setup/stations/:stationId?",
    name: "setup.stations",
    component: pending,
    meta: { mode: "setup", nav: "stations", title: "Ground stations" },
  },
  {
    path: "setup/stations/providers/:providerId?",
    name: "setup.stations.providers",
    component: pending,
    meta: { mode: "setup", nav: "stations", title: "Providers" },
  },
  {
    path: "setup/data-sources/:sourceId?",
    name: "setup.data-sources",
    component: pending,
    meta: { mode: "setup", nav: "data-sources", title: "Data sources" },
  },
  {
    path: "setup/apps/:appKey?",
    name: "setup.apps",
    component: pending,
    meta: { mode: "setup", nav: "apps", title: "Apps" },
  },
  {
    path: "setup/settings/:section?",
    name: "setup.settings",
    component: pending,
    meta: { mode: "setup", nav: "mission-settings", title: "Mission settings" },
  },
];

/** Organization group, children of /console/:org. Owner: fe-setup. */
export const setupOrgRoutes: RouteRecordRaw[] = [
  {
    path: "org/people",
    name: "org.people",
    component: pending,
    meta: { mode: "setup", nav: "people", title: "People & access", board: "People (S5)" },
  },
  {
    path: "org/people/invite",
    name: "org.people.invite",
    component: pending,
    meta: { mode: "setup", nav: "people", title: "Invite people" },
  },
  {
    path: "org/people/services",
    name: "org.people.services",
    component: pending,
    meta: { mode: "setup", nav: "people", title: "Service identities" },
  },
  {
    path: "org/missions",
    name: "org.missions",
    component: pending,
    meta: { mode: "setup", nav: "missions", title: "Missions" },
  },
  {
    path: "org/missions/new",
    name: "org.missions.new",
    component: pending,
    meta: { mode: "takeover", nav: "missions", title: "New mission" },
  },
  {
    path: "org/provider-accounts/:accountId?",
    name: "org.provider-accounts",
    component: pending,
    meta: { mode: "setup", nav: "provider-accounts", title: "Provider accounts" },
  },
  {
    path: "org/settings/:section?",
    name: "org.settings",
    component: pending,
    meta: { mode: "setup", nav: "org-settings", title: "Organization settings" },
  },
  {
    path: "org/audit",
    name: "org.audit",
    component: pending,
    meta: { mode: "setup", nav: "audit", title: "Audit log" },
  },
];
