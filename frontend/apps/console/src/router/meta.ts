import "vue-router";
import type { ConsoleRoutes } from "./route-map.ts";

/** `admin`: platform administration (L7), outside org and mission scope (ux Admin.md). */
export type ShellMode = "ops" | "setup" | "takeover" | "account" | "admin";

export type NavKey =
  | "now"
  | "fleet"
  | "alarms"
  | "commands"
  | "contacts"
  | "telemetry"
  | "timeline"
  | "readiness"
  | "spacecraft"
  | "profiles"
  | "catalog"
  | "comms"
  | "stations"
  | "contact-planning"
  | "data-sources"
  | "apps"
  | "mission-settings"
  | "people"
  | "missions"
  | "provider-accounts"
  | "org-settings"
  | "audit";

declare module "vue-router" {
  interface TypesConfig {
    RouteNamedMap: ConsoleRoutes;
  }

  interface RouteMeta {
    mode?: ShellMode;
    nav?: NavKey;
    /** Document title fragment and pending-screen heading. */
    title?: string;
    /** Canvas board this screen implements, shown on pending screens. */
    board?: string;
    /**
     * L5 auth screens: rendered in the AuthLayout without SessionProvider/AppShell; a 401 from
     * /session means anonymous there, never a redirect.
     */
    public?: boolean;
  }
}
