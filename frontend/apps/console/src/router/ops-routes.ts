import type { RouteRecordRaw } from "vue-router";
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
    // The Contacts drawer on ?contact= is the contact's page for now (backlog §2): keep the
    // documented path working by redirecting to it.
    path: "contacts/:contactId",
    name: "ops.contact",
    redirect: (to) => ({
      name: "ops.contacts",
      params: { org: to.params.org, mission: to.params.mission },
      query: { ...to.query, contact: to.params.contactId },
    }),
  },
  {
    path: "telemetry",
    name: "ops.telemetry",
    component: () => import("@/features/telemetry/TelemetryScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Telemetry" },
  },
  {
    path: "telemetry/dashboards/:dashboardId?",
    name: "ops.dashboards",
    component: () => import("@/features/telemetry/DashboardsRedirect.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Dashboards" },
  },
  {
    path: "timeline",
    name: "ops.timeline",
    component: () => import("@/features/timeline/TimelineScreen.vue"),
    meta: { mode: "ops", nav: "timeline", title: "Timeline" },
  },
];
