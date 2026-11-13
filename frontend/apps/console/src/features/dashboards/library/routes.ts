import type { RouteRecordRaw } from "vue-router";

/**
 * Slice 8 routes, unrouted until D21/D22 land (lead): add `...libraryRoutes` to ops-routes then.
 * The list sits under Telemetry › Dashboards; an item page shows versions, preview and use.
 */
export const libraryRoutes: RouteRecordRaw[] = [
  {
    path: "telemetry/dashboards/library",
    name: "ops.dashboards.library",
    component: () => import("./LibraryScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Dashboard library" },
  },
  {
    path: "telemetry/dashboards/library/:itemId",
    name: "ops.dashboards.library.item",
    component: () => import("./LibraryItemScreen.vue"),
    meta: { mode: "ops", nav: "telemetry", title: "Library widget" },
  },
];
