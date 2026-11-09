import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §A1. */
const { array, boolean, nullable, object, oneOf, string, token } = decoders;

const app = object({
  key: token,
  name: string,
  description: nullable(string),
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
