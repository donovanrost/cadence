import { array, boolean, nullable, object, string, token, type Decoded } from "./decode.ts";
import { request, type ApiResult } from "./http.ts";

/** Contract: docs/apogee/api/session.md (GET /api/console/v1/session). */
const mission = object({ id: token, slug: token, name: string });
const organization = object({
  id: token,
  slug: token,
  name: string,
  role: nullable(token),
  capabilities: array(token),
  missions: array(mission),
});

export const sessionReader = object({
  user: object({ id: token, email: string, display_name: nullable(string) }),
  current_organization_id: nullable(token),
  admin_mode: boolean,
  platform_admin_eligible: boolean,
  capabilities: array(token),
  organizations: array(organization),
  csrf_token: token,
  socket: object({ path: token }),
});

export type Session = Decoded<typeof sessionReader>;
export type SessionOrganization = Decoded<typeof organization>;
export type SessionMission = Decoded<typeof mission>;

export function fetchSession(signal?: AbortSignal): Promise<ApiResult<Session>> {
  return request("/session", sessionReader, signal ? { signal } : {});
}
