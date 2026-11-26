import type { OrganizationId } from "@/api/index.ts";
import { decoders, request, type ApiResult, type Decoded } from "@/api";
import { fleetStates } from "@/features/fleet/index.ts";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/missions` (pass-2 #11). */
const { array, boolean, integer, nullable, object, oneOf, string, token } = decoders;

const summary = object({
  id: token,
  slug: token,
  name: string,
  spacecraft_count: integer,
  worst_state: nullable(oneOf(fleetStates)),
});
export type MissionSummary = Decoded<typeof summary>;

export async function fetchMissionSummaries(
  organizationId: OrganizationId,
  signal: AbortSignal,
): Promise<ApiResult<ReadonlyMap<string, MissionSummary>>> {
  const result = await request(
    `/organizations/${encodeURIComponent(organizationId)}/missions`,
    object({ missions: array(summary, 1000) }),
    { signal },
  );
  return result.ok
    ? { ok: true, value: new Map(result.value.missions.map((m) => [m.id, m])) }
    : result;
}

const org = (organizationId: OrganizationId) =>
  `/organizations/${encodeURIComponent(organizationId)}`;

/** M1 (plans/mission-create.md, api agreed): the form's live slug check. */
const slugCheck = object({ slug: string, available: boolean, suggestion: nullable(string) });
export type MissionSlugCheck = Decoded<typeof slugCheck>;
export function checkMissionSlug(
  key: Readonly<{ organizationId: OrganizationId; slug: string }>,
  signal: AbortSignal,
): Promise<ApiResult<MissionSlugCheck>> {
  return request(
    `${org(key.organizationId)}/missions/slug?slug=${encodeURIComponent(key.slug)}`,
    slugCheck,
    { signal },
  );
}

/** M2: create in this organization. A slug clash is 422 details.slug plus details.suggestion (as AD1). */
const created = object({ mission: object({ id: token, name: string, slug: token }) });
export type CreatedMission = Decoded<typeof created>["mission"];
export async function createMission(
  organizationId: OrganizationId,
  body: Readonly<{ name: string; slug: string }>,
): Promise<ApiResult<CreatedMission>> {
  const r = await request(`${org(organizationId)}/missions`, created, { method: "POST", body });
  return r.ok ? { ok: true, value: r.value.mission } : r;
}
