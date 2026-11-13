import type { ApiError } from "@/api";
import type { SurfaceRow } from "./host.ts";

/** The app's Setup surfaces in the app's own order (ux: the tabs; no `:surface` opens the first). */
export const setupSurfaces = (rows: readonly SurfaceRow[]) =>
  [...rows].filter((s) => s.area === "setup").sort((a, b) => a.order - b.order);

/** S1 refusals the frame explains itself (ux States). */
export type HostRefusal = "not_installed" | "unknown" | null;
export function hostRefusal(e: ApiError): HostRefusal {
  if (e.kind === "conflict" && e.code === "application_not_installed") return "not_installed";
  if (e.kind === "not_found") return "unknown";
  return null;
}
