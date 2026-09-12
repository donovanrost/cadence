export type OrganizationHomeModel = {
  version: 1;
  organization: { id: string; name: string; slug: string };
  counts: { missions: number; spacecraft: number; active_memberships: number };
  recent_missions: { id: string; name: string; slug: string; created_at: string }[];
};
const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);
const identifier = (value: unknown): value is string =>
  typeof value === "string" && value.length <= 120 && /^[A-Za-z0-9][A-Za-z0-9_.:-]*$/.test(value);
const text = (value: unknown): value is string =>
  typeof value === "string" &&
  value.trim().length > 0 &&
  new TextEncoder().encode(value).length <= 800 &&
  !value.split("").some((char) => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127);
const count = (value: unknown) => Number.isSafeInteger(value) && Number(value) >= 0;
const timestamp = (value: unknown): value is string =>
  typeof value === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value) &&
  Number.isFinite(Date.parse(value));
export function readOrganizationHome(
  value: unknown,
  organizationId: unknown,
): OrganizationHomeModel {
  assertOrganizationHome(value, organizationId);
  return value;
}
function assertOrganizationHome(
  value: unknown,
  organizationId: unknown,
): asserts value is OrganizationHomeModel {
  if (
    !identifier(organizationId) ||
    !record(value) ||
    value.version !== 1 ||
    !record(value.organization) ||
    value.organization.id !== organizationId ||
    !text(value.organization.name) ||
    !text(value.organization.slug) ||
    !record(value.counts) ||
    !count(value.counts.missions) ||
    !count(value.counts.spacecraft) ||
    !count(value.counts.active_memberships) ||
    !Array.isArray(value.recent_missions) ||
    value.recent_missions.length > 3
  )
    throw Error("Invalid organization home");
  const seen = new Set<string>();
  for (const mission of value.recent_missions) {
    if (
      !record(mission) ||
      !identifier(mission.id) ||
      seen.has(mission.id) ||
      !text(mission.name) ||
      !text(mission.slug) ||
      !timestamp(mission.created_at)
    )
      throw Error("Invalid recent mission");
    seen.add(mission.id);
  }
}
export const missionHref = (id: string) => {
  if (!identifier(id)) throw Error("Invalid mission identity");
  return `/missions/${encodeURIComponent(id)}`;
};
