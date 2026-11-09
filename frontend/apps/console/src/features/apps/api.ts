import { decoders, request, type ApiResult, type Decoded } from "@/api";

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
  version: nullable(string),
  consequence_if_missing: nullable(string),
});
export const appsReader = object({ apps: array(app, 200), permissions: array(token, 50) });
export type Apps = Decoded<typeof appsReader>;
export type App = Decoded<typeof app>;

export function fetchApps(missionId: string, signal: AbortSignal): Promise<ApiResult<Apps>> {
  return request(`/missions/${encodeURIComponent(missionId)}/apps`, appsReader, { signal });
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
