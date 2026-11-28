import { isError, type ApiError } from "@/api";
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
