import { decoders as d, request, type ApiResult, type Decoded, type Reader } from "@/api";
import {
  assertFrontendApplicationCatalog,
  type FrontendApplicationCatalog,
} from "@cadence/plugin-sdk";

/**
 * L9 surface host read (docs/apogee/plans/app-surfaces.md, S1; api agreed, building): today's
 * application-host catalog for one surface, plus the app's status and its surfaces for the tabs.
 */
export const appStates = [
  "active",
  "not_installed",
  "disabled",
  "activation_pending",
  "failed",
] as const;
export const appStatus = d.object({
  state: d.oneOf(appStates),
  label: d.nullable(d.string),
  version: (v: unknown, path = "") =>
    typeof v === "number" ? String(v) : d.nullable(d.string)(v === undefined ? null : v, path),
});
export type AppStatus = Decoded<typeof appStatus>;

export const surfaceRow = d.object({
  surface_id: d.token,
  label: d.string,
  order: d.integer,
  purpose: d.token,
  area: d.oneOf(["setup", "ops"] as const),
  scope: d.oneOf(["mission", "spacecraft"] as const),
});
export type SurfaceRow = Decoded<typeof surfaceRow>;

/** The plugin-sdk check, as a reader: the catalog is the server's approved, unchanged document. */
const catalog: Reader<FrontendApplicationCatalog> = (value, path = "") => {
  try {
    assertFrontendApplicationCatalog(value);
  } catch (cause) {
    throw new d.DecodeError(path, cause instanceof Error ? cause.message : "catalog");
  }
  if (value.applications.length !== 1)
    throw new d.DecodeError(`${path}.applications`, "one surface");
  return value;
};

const hostReader = d.object({ catalog, status: appStatus, surfaces: d.array(surfaceRow, 50) });
export type SurfaceHost = Decoded<typeof hostReader>;

export type SurfaceKey = Readonly<{
  missionId: string;
  appKey: string;
  surfaceId: string;
  spacecraftId: string | null;
}>;

export function fetchSurfaceHost(
  k: SurfaceKey,
  signal: AbortSignal,
): Promise<ApiResult<SurfaceHost>> {
  const q = k.spacecraftId ? `?spacecraft_id=${encodeURIComponent(k.spacecraftId)}` : "";
  return request(
    `/missions/${encodeURIComponent(k.missionId)}/apps/${encodeURIComponent(k.appKey)}/surfaces/${encodeURIComponent(k.surfaceId)}/host${q}`,
    hostReader,
    { signal },
  );
}

/** Status tag (ux AppSurfaces.md): `■ ACTIVE` / `○ NOT INSTALLED` / `▲ ACTIVATION PENDING` / `◆ FAILED`. */
export const statusTag: Readonly<
  Record<AppStatus["state"], { state: "nominal" | "off" | "caution" | "crit"; label: string }>
> = {
  active: { state: "nominal", label: "Active" },
  not_installed: { state: "off", label: "Not installed" },
  disabled: { state: "off", label: "Disabled" },
  activation_pending: { state: "caution", label: "Activation pending" },
  failed: { state: "crit", label: "Failed" },
};
