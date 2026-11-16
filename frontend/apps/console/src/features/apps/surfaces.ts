import type { RouteLocationRaw } from "vue-router";
import { isError, isKeyOf, type ApiError } from "@/api";
import type { SurfaceRow } from "./host.ts";

/** The app's Setup surfaces in the app's own order (ux: the tabs; no `:surface` opens the first). */
export const setupSurfaces = (rows: readonly SurfaceRow[]) =>
  [...rows].filter((s) => s.area === "setup").sort((a, b) => a.order - b.order);

/** S1 refusals the frame explains itself (ux States). */
export type HostRefusal = "not_installed" | "unknown" | null;
export function hostRefusal(e: ApiError): HostRefusal {
  if (isError(e, "application_not_installed")) return "not_installed";
  if (e.kind === "not_found") return "unknown";
  return null;
}

/**
 * The query keys each app's surface query accepts (ux U42; until the app descriptor lists them). The
 * server refuses an unknown key and the surface fails, so only these go to the bridge as params.
 */
const SURFACE_QUERY_KEYS = {
  derived_telemetry: [
    "definition",
    "version",
    "q",
    "values_q",
    "spacecraft",
    "spacecraft_q",
    "page",
    "history_page",
    "values_page",
    "sources_page",
    "spacecraft_page",
  ],
} as const satisfies Readonly<Record<string, readonly string[]>>;

/** The host-captured params for an app's surface query: its declared keys, single values only. */
export function surfaceParams(
  appKey: string,
  query: Readonly<Record<string, unknown>>,
): Record<string, string> {
  return Object.fromEntries(
    (isKeyOf(SURFACE_QUERY_KEYS, appKey) ? SURFACE_QUERY_KEYS[appKey] : []).flatMap((k) => {
      const v = query[k];
      return typeof v === "string" ? [[k, v]] : [];
    }),
  );
}

/**
 * A surface's own link (`/missions/:m/applications/:app/:surface?…`, the legacy host's paths) as a
 * console target in this mission, so in-surface navigation stays in the SPA. Null for anything else.
 */
export function surfaceLink(
  href: string,
  missionId: string,
): Readonly<{ appKey: string; surface: string; query: Record<string, string> }> | null {
  const url = new URL(href, "http://console.invalid");
  const [, mission, appKey, surface] =
    /^\/missions\/([^/]+)\/applications\/([^/]+)\/([^/]+)\/?$/.exec(url.pathname) ?? [];
  if (!mission || !appKey || !surface || decodeURIComponent(mission) !== missionId) return null;
  return {
    appKey: decodeURIComponent(appKey),
    surface: decodeURIComponent(surface),
    query: Object.fromEntries(url.searchParams),
  };
}

/**
 * Surfaces an app no longer has, with their console home (ux, sweep row 2): a bookmark or old link
 * lands there instead of on an unknown-surface notice. Spacecraft's create/edit forms saved directly;
 * Setup's reviewed pages own them now.
 */
export function retiredSurfaceHome(
  appKey: string,
  surface: string,
  spacecraftId: string | null,
): RouteLocationRaw | null {
  if (appKey !== "spacecraft") return null;
  if (surface === "new") return { name: "setup.spacecraft.new" };
  if (surface === "profile_new") return { name: "setup.profile.new" };
  if (surface === "edit") {
    return spacecraftId
      ? { name: "setup.spacecraft.one", params: { spacecraftId } }
      : { name: "setup.spacecraft" };
  }
  return null;
}

/**
 * App surfaces that show or edit one record, with the console screen that owns that record (lead,
 * qa 11-16). Opened from a tab they'd have no record id: the host binds a surface's route params and
 * callers can't supply them. So they leave the tab bar, and a direct open (an old link or bookmark)
 * goes to the console screen, carrying the id when the link has one. The list is explicit because a
 * surface's purpose can't tell Edit from New (both are `configuration`).
 */
export function subjectSurfaceHome(
  appKey: string,
  surface: string,
  query: Readonly<Record<string, unknown>>,
): RouteLocationRaw | null {
  if (appKey !== "comms") return null;
  const id = (key: string) => {
    const value = query[key];
    return typeof value === "string" && value !== "" ? value : null;
  };
  if (surface === "ground_station" || surface === "ground_station_edit") {
    const stationId = id("ground_station_id");
    return stationId
      ? { name: "setup.stations", params: { stationId } }
      : { name: "setup.stations" };
  }
  if (surface === "transport") {
    const transportId = id("transport_id");
    return transportId
      ? { name: "setup.comms.transports", params: { transportId } }
      : { name: "setup.comms.transports" };
  }
  // The console has no single routing-rule screen; its rules list lives on Setup › Comms.
  if (surface === "routing_detail") return { name: "setup.comms" };
  return null;
}

/** Whether a surface needs a record and so stays out of the tab bar (subjectSurfaceHome). */
export const isSubjectSurface = (appKey: string, surface: string) =>
  subjectSurfaceHome(appKey, surface, {}) !== null;
