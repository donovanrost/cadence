import {
  observation,
  record,
  text,
  identifier,
  organization,
  type Organization,
  type Observation,
} from "../../shared/platform-contract";
export type Cursor = { after_slug: string; after_id: string };
export type OrganizationDirectory = Observation & {
  limit: 50;
  query: Partial<Cursor>;
  organizations: Organization[];
  next_cursor: Cursor | null;
};
function cursor(value: unknown): value is Cursor {
  return (
    record(value) &&
    Object.keys(value).length === 2 &&
    text(value.after_slug) &&
    identifier(value.after_id)
  );
}
export function readOrganizationDirectory(value: unknown, userId: unknown): OrganizationDirectory {
  observation(value, userId);
  if (
    value.limit !== 50 ||
    !record(value.query) ||
    (Object.keys(value.query).length > 0 && !cursor(value.query)) ||
    !Array.isArray(value.organizations) ||
    value.organizations.length > 50 ||
    (value.next_cursor !== null && !cursor(value.next_cursor))
  )
    throw Error("Invalid organization directory");
  const organizations: unknown[] = value.organizations;
  const seen = new Set<string>();
  for (const item of organizations) {
    organization(item);
    if (seen.has(item.id)) throw Error("Duplicate organization");
    seen.add(item.id);
  }
  if (value.next_cursor !== null) {
    const last = organizations.at(-1);
    organization(last);
    if (
      value.organizations.length !== 50 ||
      value.next_cursor.after_id !== last.id ||
      value.next_cursor.after_slug !== last.slug
    )
      throw Error("Invalid directory continuation");
  }
  return value as OrganizationDirectory;
}
export function directoryHref(value?: Cursor | null) {
  if (!value) return "/admin/organizations";
  if (!cursor(value)) throw Error("Invalid directory cursor");
  return `/admin/organizations?${new URLSearchParams(value).toString()}`;
}
