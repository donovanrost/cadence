import type { RouteRecordRaw } from "vue-router";
import { pending } from "./pending.ts";

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
    component: pending,
    meta: { mode: "ops", nav: "fleet", title: "Fleet" },
  },
  {
    path: "fleet/:scId(\\d+)/:tab(investigate|telemetry|uplink|passes|configuration|history)?",
    name: "ops.spacecraft",
    component: () => import("@/features/investigate/SpacecraftScreen.vue"),
    meta: { mode: "ops", nav: "fleet", title: "Spacecraft", board: "Investigate (J2)" },
  },
  {
    path: "alarms",
    name: "ops.alarms",
    component: pending,
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
    component: pending,
    meta: { mode: "ops", nav: "contacts", title: "Contacts", board: "Contacts (J4)" },
  },
  {
    path: "contacts/plan",
    name: "ops.contacts.plan",
    component: pending,
    meta: {
      mode: "ops",
      nav: "contacts",
      title: "Plan contacts",
      board: "PassPrediction (K0), SchedulePlan (K1)",
    },
  },
  {
    path: "contacts/replan/:stationId",
    name: "ops.contacts.replan",
    component: pending,
    meta: { mode: "ops", nav: "contacts", title: "Replan", board: "Replan (K2)" },
  },
  {
    path: "contacts/review",
    name: "ops.contacts.review",
    component: pending,
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
    component: pending,
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
    component: pending,
    meta: { mode: "ops", nav: "timeline", title: "Timeline" },
  },
];
