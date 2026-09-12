export const record = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === "object" && !Array.isArray(value);
export const identifier = (value: unknown): value is string =>
  typeof value === "string" && /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,119}$/.test(value);
export const text = (value: unknown, max = 800): value is string =>
  typeof value === "string" &&
  value.trim().length > 0 &&
  new TextEncoder().encode(value).length <= max &&
  !value.split("").some((char) => char.charCodeAt(0) < 32 || char.charCodeAt(0) === 127);
export type Observation = { version: 1; user_id: string; observed_at: string };
export function observation(
  value: unknown,
  userId: unknown,
): asserts value is Observation & Record<string, unknown> {
  if (
    !identifier(userId) ||
    !record(value) ||
    value.version !== 1 ||
    value.user_id !== userId ||
    typeof value.observed_at !== "string" ||
    !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(value.observed_at) ||
    !Number.isFinite(Date.parse(value.observed_at))
  )
    throw Error("Invalid administrator observation");
}
export type Organization = { id: string; name: string; slug: string };
export function organization(value: unknown): asserts value is Organization {
  if (!record(value) || !identifier(value.id) || !text(value.name) || !text(value.slug))
    throw Error("Invalid organization");
}
export function organizationHref(id: string) {
  if (!identifier(id)) throw Error("Invalid organization identity");
  return `/admin/organizations/${encodeURIComponent(id)}`;
}
