import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import "./meta.ts";
import { opsRoutes } from "./ops-routes.ts";
import { setupMissionRoutes, setupOrgRoutes } from "./setup-routes.ts";

export type { NavKey, ShellMode } from "./meta.ts";

const routes: RouteRecordRaw[] = [
  { path: "/", name: "home", component: () => import("@/shell/ConsoleHome.vue") },
  {
    path: "/account",
    name: "account",
    component: () => import("@/features/account/AccountScreen.vue"),
    meta: { mode: "account", title: "Your account" },
  },
  ...(import.meta.env.DEV
    ? [
        {
          path: "/kit",
          name: "kit",
          component: () => import("@/features/kit/KitScreen.vue"),
          meta: { mode: "account" as const, title: "Kit" },
        },
      ]
    : []),
  {
    path: "/:org",
    children: [
      { path: "", name: "org.home", component: () => import("@/shell/ConsoleHome.vue") },
      ...setupOrgRoutes,
      {
        path: ":mission",
        children: [
          { path: "", name: "mission.home", redirect: { name: "ops.now" } },
          ...opsRoutes,
          ...setupMissionRoutes,
        ],
      },
    ],
  },
  {
    path: "/:pathMatch(.*)*",
    name: "not-found",
    component: () => import("@/shell/NotFoundScreen.vue"),
    meta: { mode: "account", title: "Not found" },
  },
];

export function createConsoleRouter() {
  return createRouter({ history: createWebHistory("/console/"), routes });
}
