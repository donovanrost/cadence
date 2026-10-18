import {
  observation,
  organization,
  record,
  identifier,
  text,
  organizationHref,
  type Organization,
  type Observation,
} from "../../shared/platform-contract";
export type Page<T> = { entries: T[]; next_after: string | null };
export type Member = {
  id: string;
  user_id: string;
  name: string;
  email: string;
  role: "member" | "organization_admin";
  user_state: "active" | "disabled";
};
export type Invitation = {
  id: string;
  email: string;
  role: "member" | "organization_admin";
  grant_platform_admin: boolean;
  expires_at: string;
};
export type Service = {
  id: string;
  name: string;
  mission_id: string | null;
  token_hint: string | null;
  lifecycle_state: "active" | "disabled";
  capabilities: ("organization_admin" | "mission_admin")[];
};
export type Query = { members_after: string; invitations_after: string; services_after: string };
export type OrganizationDetail = Observation & {
  organization: Organization;
  limit: 25;
  query: Query;
  members: Page<Member>;
  invitations: Page<Invitation>;
  services: Page<Service>;
  issued_identity: { id: string; name: string } | null;
};
const roles = ["member", "organization_admin"];
const states = ["active", "disabled"];
const keys = ["members_after", "invitations_after", "services_after"];
const timestamp = (v: unknown): v is string =>
  typeof v === "string" &&
  /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/.test(v) &&
  Number.isFinite(Date.parse(v));
function page(value: unknown, row: (value: Record<string, unknown>) => boolean) {
  if (
    !record(value) ||
    !Array.isArray(value.entries) ||
    value.entries.length > 25 ||
    (value.next_after !== null && !identifier(value.next_after))
  )
    throw Error("Invalid detail page");
  const entries: unknown[] = value.entries;
  let lastId: string | undefined;
  const ids = new Set();
  for (const item of entries) {
    if (!record(item) || !identifier(item.id) || ids.has(item.id) || !row(item))
      throw Error("Invalid detail row");
    ids.add(item.id);
    lastId = item.id;
  }
  if (value.next_after !== null && (value.entries.length !== 25 || value.next_after !== lastId))
    throw Error("Invalid detail continuation");
}
function query(value: unknown): value is Query {
  return (
    record(value) &&
    Object.keys(value).length === 3 &&
    keys.every((k) => value[k] === "" || identifier(value[k]))
  );
}
export function readOrganizationDetail(
  value: unknown,
  userId: unknown,
  organizationId: unknown,
): OrganizationDetail {
  observation(value, userId);
  organization(value.organization);
  if (value.organization.id !== organizationId || value.limit !== 25 || !query(value.query))
    throw Error("Invalid organization context");
  page(
    value.members,
    (r) =>
      identifier(r.user_id) &&
      text(r.name) &&
      text(r.email) &&
      roles.includes(String(r.role)) &&
      states.includes(String(r.user_state)),
  );
  page(
    value.invitations,
    (r) =>
      text(r.email) &&
      roles.includes(String(r.role)) &&
      typeof r.grant_platform_admin === "boolean" &&
      timestamp(r.expires_at),
  );
  page(
    value.services,
    (r) =>
      text(r.name) &&
      (r.mission_id === null || identifier(r.mission_id)) &&
      (r.token_hint === null || text(r.token_hint, 120)) &&
      states.includes(String(r.lifecycle_state)) &&
      Array.isArray(r.capabilities) &&
      r.capabilities.length <= 2 &&
      new Set(r.capabilities).size === r.capabilities.length &&
      r.capabilities.every((c) => c === "organization_admin" || c === "mission_admin"),
  );
  if (
    value.issued_identity !== null &&
    (!record(value.issued_identity) ||
      !identifier(value.issued_identity.id) ||
      !text(value.issued_identity.name))
  )
    throw Error("Invalid issuance observation");
  return value as OrganizationDetail;
}
export function detailHref(id: string, values: Query, change: Partial<Query> = {}) {
  const next = { ...values, ...change };
  if (!query(next)) throw Error("Invalid detail query");
  const search = new URLSearchParams(Object.entries(next).filter(([, v]) => v !== "")).toString();
  return organizationHref(id) + (search ? `?${search}` : "");
}
export type Input = { display_name: string; service_identity_id: string };
export type Act = (event: "issue_service_identity", input: Input) => Promise<unknown>;
export type Token = { id: string; name: string; api_token: string };
export function readIssueResult(
  value: unknown,
):
  | { status: "issued"; identity: Token }
  | { status: "invalid"; errors: Record<string, string> }
  | { status: "unavailable" } {
  if (!record(value)) throw Error("Invalid issuance result");
  if (value.status === "unavailable") return { status: "unavailable" };
  if (
    value.status === "invalid" &&
    record(value.errors) &&
    Object.keys(value.errors).length &&
    Object.entries(value.errors).every(
      ([k, v]) => ["form", "display_name", "service_identity_id"].includes(k) && text(v, 200),
    )
  )
    return value as { status: "invalid"; errors: Record<string, string> };
  if (
    value.status === "issued" &&
    record(value.identity) &&
    identifier(value.identity.id) &&
    text(value.identity.name) &&
    text(value.identity.api_token, 512)
  )
    return value as { status: "issued"; identity: Token };
  throw Error("Invalid issuance result");
}
