import type { RouteRecordRaw } from "vue-router";
import { pending } from "./pending.ts";
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
    component: pending,
    meta: { mode: "ops", nav: "commands", title: "Commands", board: "CommandFlow" },
  },
  {
    path: "commands/new",
    name: "ops.commands.new",
    component: pending,
    meta: { mode: "ops", nav: "commands", title: "Compose", board: "Compose (C1), Command (J3)" },
  },
  {
    path: "commands/:requestId/:view(review|uplink)?",
    name: "ops.commands.request",
    component: pending,
    meta: { mode: "ops", nav: "commands", title: "Command request", board: "Approve, Uplink" },
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
    // K2 v1 (DECISIONS #25): re-plan after provider changes, ?plan= or ?reservation=. The
    // station-down entry (contacts/replan/:stationId) returns with S7.
    path: "contacts/replan",
    name: "ops.contacts.replan",
    component: () => import("@/features/scheduling/ReplanScreen.vue"),
    meta: { mode: "takeover", nav: "contacts", title: "Re-plan", board: "Replan (K2)" },
  },
  {
    path: "contacts/review",
    name: "ops.contacts.review",
    component: pending,
    // K3 waits for S9 (DECISIONS #25); not linked from anywhere until then.
    meta: { mode: "ops", nav: "contacts", title: "Pass review", board: "PassReview (K3)" },
  },
  {
    path: "contacts/:contactId",
    name: "ops.contact",
    component: pending,
    meta: { mode: "ops", nav: "contacts", title: "Contact" },
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
    component: pending,
    meta: { mode: "ops", nav: "telemetry", title: "Dashboards" },
  },
  {
    path: "timeline",
    name: "ops.timeline",
    component: () => import("@/features/timeline/TimelineScreen.vue"),
    meta: { mode: "ops", nav: "timeline", title: "Timeline" },
  },
];
