import type { MissionId } from "@/api/index.ts";
import {
  actor,
  decoders as d,
  request,
  type ApiResult,
  type Decoded,
  type Reader,
  type SpacecraftId,
} from "@/api";
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
  state: d.known(appStates),
  label: d.nullable(d.string),
  /** Asked of api (ux #77): the open activation request, for "Waiting for activation approval · …". */
  activation_request: (v: unknown, path = "") =>
    v === undefined
      ? null
      : d.nullable(
          d.object({
            requested_by: d.nullable(actor),
            requested_at: d.timestamp,
          }),
        )(v, path),
  version: (v: unknown, path = "") =>
    typeof v === "number" ? String(v) : d.nullable(d.string)(v === undefined ? null : v, path),
});
export type AppStatus = Decoded<typeof appStatus>;

export const surfaceRow = d.object({
  surface_id: d.token,
  label: d.string,
  order: d.integer,
  purpose: d.known([
    "overview",
    "collection",
    "configuration",
    "operations",
    "activity",
    "subject_detail",
  ] as const),
  area: d.known(["setup", "ops"] as const),
  scope: d.known(["mission", "spacecraft"] as const),
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
  missionId: MissionId;
  appKey: string;
  surfaceId: string;
  spacecraftId: SpacecraftId | null;
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
  Record<
    AppStatus["state"],
    { state: "nominal" | "off" | "caution" | "crit" | "stale"; label: string }
  >
> = {
  active: { state: "nominal", label: "Active" },
  not_installed: { state: "off", label: "Not installed" },
  disabled: { state: "off", label: "Disabled" },
  activation_pending: { state: "caution", label: "Activation pending" },
  failed: { state: "crit", label: "Failed" },
  unrecognized: { state: "stale", label: "Status not known" },
};

/** ux #77: `Waiting for activation approval · requested by Mira K. at 02:10Z`. */
export function pendingLine(status: AppStatus, at: (iso: string) => string): string | null {
  if (status.state !== "activation_pending") return null;
  const r = status.activation_request;
  if (!r) return "Waiting for activation approval";
  const by = r.requested_by?.name ? ` by ${r.requested_by.name}` : "";
  return `Waiting for activation approval · requested${by} at ${at(r.requested_at)}`;
}
