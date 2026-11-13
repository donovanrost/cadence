import { decoders, request, type ApiResult, type Decoded, type SpacecraftId } from "@/api";
import { appStatus, surfaceRow } from "./host.ts";

/** Contract: docs/apogee/api/setup.md, `GET /missions/:id/apps` (A1). */
const { array, boolean, nullable, object, oneOf, string, token } = decoders;

const app = object({
  key: token,
  name: string,
  description: nullable(string),
  /** Always on; can't be installed, disabled or removed. */
  platform: decoders.optional(boolean),
  installed: boolean,
  state: oneOf(["installed", "disabled", "not_installed"]),
  /** Installed version (an integer today), shown as text; null when not installed. */
  version: (v: unknown, path = "") =>
    typeof v === "number" ? String(v) : nullable(string)(v === undefined ? null : v, path),
  consequence_if_missing: nullable(string),
  /** L9 (A1 extension, asked of api): the app's status and its surfaces; absent on older servers. */
  status: (v: unknown, path = "") => (v === undefined ? null : nullable(appStatus)(v, path)),
  surfaces: (v: unknown, path = "") => (v === undefined ? [] : array(surfaceRow, 50)(v, path)),
});
export const appsReader = object({ apps: array(app, 200), permissions: array(token, 50) });
export type Apps = Decoded<typeof appsReader>;
export type App = Decoded<typeof app>;

export function fetchApps(missionId: string, signal: AbortSignal): Promise<ApiResult<Apps>> {
  return request(`/missions/${encodeURIComponent(missionId)}/apps`, appsReader, { signal });
}

/** Off until api serves L19's read (a 404 on the spacecraft page trips qa's e2e diagnostics guard). */
export const SPACECRAFT_APPS_LIVE = false;

/** Mission apps (A1), or one spacecraft's (L19, plans/spacecraft-apps.md: the same row shape). */
export type AppsKey = Readonly<{ missionId: string; spacecraftId: SpacecraftId | null }>;
export function fetchScopedApps(k: AppsKey, signal: AbortSignal): Promise<ApiResult<Apps>> {
  const m = `/missions/${encodeURIComponent(k.missionId)}`;
  const path = k.spacecraftId
    ? `${m}/spacecraft/${encodeURIComponent(k.spacecraftId)}/apps`
    : `${m}/apps`;
  return request(path, appsReader, { signal });
}

export type AppAction = "install" | "disable" | "uninstall";

/**
 * The app-change seam (Changes.md §6, domain decision 2026-11-09): v1 applies directly
 * (`applied`); when `application_installation` becomes a change-set kind this returns `staged`
 * and the screen doesn't change.
 */
export type AppChangeOutcome =
  | Readonly<{ kind: "applied"; app: App }>
  | Readonly<{ kind: "staged" }>
  | Readonly<{ kind: "failed"; error: import("@/api").ApiError }>;

export async function changeApp(
  missionId: string,
  key: string,
  action: AppAction,
): Promise<AppChangeOutcome> {
  const result = await request(
    `/missions/${encodeURIComponent(missionId)}/apps/${encodeURIComponent(key)}/${action}`,
    app,
    { method: "POST", body: {} },
  );
  return result.ok
    ? { kind: "applied", app: result.value }
    : { kind: "failed", error: result.error };
}
