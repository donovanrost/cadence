import {
  array,
  boolean,
  integer,
  nullable,
  object,
  optional,
  string,
  timestamp,
  token,
  type Decoded,
} from "./decode.ts";
import { role } from "./entities.ts";
import { missionId, organizationId as organizationIdReader } from "./ids.ts";
import { request, type ApiResult } from "./http.ts";

/** Contract: docs/apogee/api/session.md (GET /api/v1/session). */
/** §12C: the id is a MissionId (what the API takes); the slug is only for routes. */
const mission = object({ id: missionId, slug: token, name: string });
const organization = object({
  id: organizationIdReader,
  slug: token,
  name: string,
  role: nullable(role),
  capabilities: array(token),
  missions: array(mission),
});

export const sessionReader = object({
  user: object({ id: token, email: string, display_name: nullable(string) }),
  current_organization_id: nullable(organizationIdReader),
  admin_mode: boolean,
  /** api-ops L6: when admin mode ends (ISO); null when off or unknown. */
  admin_mode_expires_at: optional(nullable(timestamp)),
  platform_admin_eligible: boolean,
  /** api cfdf79f7: pending invitations for my email (L21; the org switcher footer). */
  pending_invitations_count: optional(nullable(integer)),
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

/**
 * #664: signs this browser out (`DELETE /session`, 204). The server revokes the session, disconnects
 * its live sockets and drops the cookie; the caller then leaves with a full navigation, since the
 * CSRF token and every cached read belonged to that session.
 */
export function signOut(): Promise<ApiResult<null>> {
  return request("/session", () => null, { method: "DELETE" });
}
