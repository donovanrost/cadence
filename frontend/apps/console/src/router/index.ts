import { createRouter, createWebHistory, type RouteRecordRaw } from "vue-router";
import "./meta.ts";
import { opsRoutes } from "./ops-routes.ts";
import { setupMissionRoutes, setupOrgRoutes } from "./setup-routes.ts";

export type { NavKey, ShellMode } from "./meta.ts";

const routes: RouteRecordRaw[] = [
  { path: "/", name: "home", component: () => import("@/shell/ConsoleHome.vue") },
  // L5 public auth screens (lead; ux Auth.md); api-ops 302s the old /sign-in and /invitations here.
  {
    path: "/sign-in",
    name: "auth.sign-in",
    component: () => import("@/features/auth/SignInScreen.vue"),
    meta: { public: true, title: "Sign in" },
  },
  {
    path: "/invitations/:token",
    name: "auth.invitation",
    component: () => import("@/features/auth/InvitationScreen.vue"),
    meta: { public: true, title: "Invitation" },
  },
  {
    path: "/no-organization",
    name: "auth.no-org",
    component: () => import("@/features/auth/NoOrganizationScreen.vue"),
    meta: { public: true, title: "No organization" },
  },
  // L7 platform admin (ux screens/Admin.md): outside org and mission scope, behind admin mode (L6).
  {
    path: "/admin",
    component: () => import("@/features/admin/AdminLayout.vue"),
    meta: { mode: "admin", title: "Platform admin" },
    children: [
      { path: "", name: "admin", redirect: { name: "admin.organizations" } },
      {
        path: "organizations",
        name: "admin.organizations",
        component: () => import("@/features/admin/OrganizationsScreen.vue"),
        meta: { mode: "admin", title: "Organizations" },
      },
      {
        path: "organizations/:orgId",
        name: "admin.organization",
        component: () => import("@/features/admin/OrganizationScreen.vue"),
        meta: { mode: "admin", title: "Organization" },
      },
      {
        path: "service-identities",
        name: "admin.service-identities",
        component: () => import("@/features/admin/ServiceIdentitiesScreen.vue"),
        meta: { mode: "admin", title: "Service identities" },
      },
      {
        path: "runtime",
        name: "admin.runtime",
        component: () => import("@/features/admin/RuntimeScreen.vue"),
        meta: { mode: "admin", title: "Runtime" },
      },
      {
        path: "audit",
        name: "admin.audit",
        component: () => import("@/features/admin/AuditScreen.vue"),
        meta: { mode: "admin", title: "Platform audit" },
      },
    ],
  },
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
