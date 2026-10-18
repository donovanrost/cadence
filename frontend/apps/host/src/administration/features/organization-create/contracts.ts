import {
  observation,
  record,
  organization,
  text,
  type Organization,
  type Observation,
} from "../../shared/platform-contract";
export type OrganizationCreate = Observation & { created: Organization | null };
export type Input = { display_name: string; slug: string };
export type Act = (event: "create", input: Input) => Promise<unknown>;
export type Result =
  | { status: "created"; organization: Organization }
  | { status: "invalid"; errors: Record<string, string> }
  | { status: "unavailable" };
export function readOrganizationCreate(value: unknown, userId: unknown): OrganizationCreate {
  observation(value, userId);
  if (value.created !== null) organization(value.created);
  return value as OrganizationCreate;
}
export function readResult(value: unknown): Result {
  if (!record(value)) throw Error("Invalid creation result");
  if (value.status === "created") {
    organization(value.organization);
    return value as Result;
  }
  if (value.status === "unavailable") return { status: "unavailable" };
  if (
    value.status === "invalid" &&
    record(value.errors) &&
    Object.keys(value.errors).length > 0 &&
    Object.entries(value.errors).every(
      ([key, message]) => ["form", "display_name", "slug"].includes(key) && text(message, 200),
    )
  )
    return value as Result;
  throw Error("Invalid creation result");
}
