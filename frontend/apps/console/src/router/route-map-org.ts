import type { RouteRecordInfo } from "vue-router";
import type { Raw, RawOpt, Plain, InOrg, InMission } from "./route-types.ts";

/** Shell, account, org and admin routes (no mission). Part of ConsoleRoutes (route-map.ts). */
export interface OrgRoutes {
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
}
