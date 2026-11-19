import type { RouteRecordRaw } from "vue-router";
import { paramText } from "@/shell/route-params.ts";
import { responsive } from "./responsive.ts";

/**
 * Ops mode, children of /console/:org/:mission. Owner: fe-ops (swap `pending` for your screen).
 * Route names are stable API: the rail, ⌘K and cross-links use them.
 */
export const opsRoutes: RouteRecordRaw[] = [
  {
    path: "now",
    name: "ops.now",
    component: () => import("@/features/now/NowScreen.vue"),
    meta: { mode: "ops", nav: "now", title: "Now", board: "Now (J1)" },
  },
  {
    path: "fleet",
    name: "ops.fleet",
    component: () => import("@/features/fleet/FleetScreen.vue"),
    meta: { mode: "ops", nav: "fleet", title: "Fleet" },
  },
  {
    path: "fleet/:scId(\\d+)/:tab(investigate|telemetry|uplink|passes|configuration|history)?",
    name: "ops.spacecraft",
    // Under 768 the on-call paged view (Mobile.md J6) replaces the console layout.
    component: responsive(
      () => import("@/features/investigate/SpacecraftScreen.vue"),
      () => import("@/features/mobile/MobileAlarmScreen.vue"),
    ),
    meta: { mode: "ops", nav: "fleet", title: "Spacecraft", board: "Investigate (J2)" },
  },
  {
    path: "alarms",
    name: "ops.alarms",
    component: () => import("@/features/alarms/AlarmsScreen.vue"),
    meta: { mode: "ops", nav: "alarms", title: "Alarms" },
  },
  {
    path: "commands",
    name: "ops.commands",
    component: () => import("@/features/commands/list/CommandsScreen.vue"),
    meta: { mode: "ops", nav: "commands", title: "Commands", board: "CommandFlow" },
  },
  {
    path: "commands/new",
    name: "ops.commands.new",
    component: () => import("@/features/commands/compose/ComposeScreen.vue"),
    meta: {
      mode: "takeover",
      nav: "commands",
      title: "Compose",
      board: "Compose (C1), Command (J3)",
    },
  },
  {
    path: "commands/:requestId/:view(review|uplink)?",
    name: "ops.commands.request",
    component: () => import("@/features/commands/request/RequestScreen.vue"),
    meta: { mode: "takeover", nav: "commands", title: "Command request", board: "Approve, Uplink" },
  },
  {
    path: "contacts",
    name: "ops.contacts",
    component: () => import("@/features/contacts/ContactsScreen.vue"),
    meta: { mode: "ops", nav: "contacts", title: "Contacts", board: "Contacts (J4)" },
  },
  {
    // K1 (lead, DECISIONS #24): takeover console. K0 has no route (DECISIONS #4).
    path: "contacts/plan",
    name: "ops.contacts.plan",
    component: () => import("@/features/scheduling/PlanScreen.vue"),
    meta: { mode: "takeover", nav: "contacts", title: "Plan contacts", board: "SchedulePlan (K1)" },
  },
  {
    // K2 station-down entry (S7, fe-setup): same screen, branches on route.params.stationId.
    path: "contacts/replan/:stationId",
    name: "ops.contacts.replan.station",
    component: () => import("@/features/replan/ReplanScreen.vue"),
    meta: { mode: "takeover", nav: "contacts", title: "Re-plan", board: "Replan (K2)" },
  },
  {
    // K2 v1 (DECISIONS #25): re-plan after provider changes, ?plan= (fe-setup, DECISIONS #43).
    path: "contacts/replan",
    name: "ops.contacts.replan",
    component: () => import("@/features/replan/ReplanScreen.vue"),
    meta: { mode: "takeover", nav: "contacts", title: "Re-plan", board: "Replan (K2)" },
  },
  {
    path: "contacts/review",
    name: "ops.contacts.review",
    // K3 Close the books over S9 (fe-setup, DECISIONS #43/#47).
    component: () => import("@/features/review/ReviewScreen.vue"),
    meta: { mode: "ops", nav: "contacts", title: "Pass review", board: "PassReview (K3)" },
  },
  {
    // §11c(C) A12 (ux U78): the contact ledgers beyond the Live window, a week at a time. Before
    // contacts/:contactId so 'history' isn't read as a contact id.
    path: "contacts/history",
    name: "ops.contacts.history",
    component: () => import("@/features/contacts/history/HistoryScreen.vue"),
    meta: { mode: "ops", nav: "contacts", title: "Contact history", board: "ContactHistory (A12)" },
  },
  {
    // The Contacts drawer on ?contact= is the contact's page for now (backlog §2): keep the
    // documented path working by redirecting to it.
    path: "contacts/:contactId",
    name: "ops.contact",
    redirect: (to) => ({
      name: "ops.contacts",
      query: { ...to.query, contact: paramText(to.params, "contactId") },
    }),
  },
  {
    path: "telemetry",
    name: "ops.telemetry",
    component: () => import("@/features/telemetry/TelemetryScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Telemetry" },
  },
  {
    // Dashboards directory (dashboards, L8): Ops › Telemetry › Dashboards (ux Dashboards.md).
    path: "telemetry/dashboards",
    name: "ops.dashboards",
    component: () => import("@/features/dashboards/directory/DirectoryScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Dashboards" },
  },
  {
    path: "telemetry/dashboards/new",
    name: "ops.dashboards.new",
    component: () => import("@/features/dashboards/directory/NewDashboardScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "New dashboard" },
  },
  // Dashboards' slice 5, 6 and 8 screens (plans/dashboards.md), live since their endpoints landed.
  {
    path: "telemetry/dashboards/library",
    name: "ops.dashboards.library",
    // D21/D22 (api ffd5c6d69).
    component: () => import("@/features/dashboards/library/LibraryScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Dashboard library" },
  },
  {
    path: "telemetry/dashboards/library/:itemId",
    name: "ops.dashboards.library.item",
    component: () => import("@/features/dashboards/library/LibraryItemScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Library widget" },
  },
  {
    path: "telemetry/dashboards/playlists",
    name: "ops.dashboards.playlists",
    // D23/D24 (api 475cf1295).
    component: () => import("@/features/dashboards/playlists/PlaylistsScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Playlists" },
  },
  {
    path: "telemetry/dashboards/playlists/:playlistId/present",
    name: "ops.dashboards.present",
    component: () => import("@/features/dashboards/playlists/PresentScreen.vue"),
    meta: { mode: "takeover", nav: "telemetry", title: "Present playlist" },
  },
  {
    path: "telemetry/dashboards/shares/:shareId",
    name: "ops.dashboards.share",
    // D20 (api f622f0772).
    component: () => import("@/features/dashboards/shared/SharedViewScreen.vue"),
    meta: { mode: "takeover", nav: "telemetry", title: "Shared dashboard" },
  },
  {
    path: "telemetry/dashboards/snapshots/:snapshotId",
    name: "ops.dashboards.snapshot",
    component: () => import("@/features/dashboards/shared/SharedViewScreen.vue"),
    meta: { mode: "takeover", nav: "telemetry", title: "Dashboard snapshot" },
  },
  {
    path: "telemetry/dashboards/:dashboardId/settings/:tab?",
    name: "ops.dashboard.settings",
    // D14–D19 (api f4ef739b9, fc222221).
    component: () => import("@/features/dashboards/settings/SettingsScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Dashboard settings" },
  },
  {
    // Dashboard viewer (dashboards, L8): a takeover cockpit (ux Dashboards.md).
    path: "telemetry/dashboards/:dashboardId",
    name: "ops.dashboard",
    component: () => import("@/features/dashboards/viewer/DashboardScreen.vue"),
    meta: { mode: "takeover", nav: "telemetry", title: "Dashboard" },
  },
  {
    // `/edit` opens the viewer in edit mode (user decision 2026-10-08).
    path: "telemetry/dashboards/:dashboardId/edit",
    name: "ops.dashboard.edit",
    redirect: (to) => ({
      name: "ops.dashboard",
      params: { dashboardId: paramText(to.params, "dashboardId") },
      query: { ...to.query, edit: "1" },
    }),
  },
  {
    path: "timeline",
    name: "ops.timeline",
    component: () => import("@/features/timeline/TimelineScreen.vue"),
    meta: { mode: "ops", nav: "timeline", title: "Timeline" },
  },
];
