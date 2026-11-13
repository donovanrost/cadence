import { codeOf, recordOf } from "@/api";
import {
  decoders as d,
  request,
  type ApiError,
  type ApiResult,
  type Decoded,
  outcomeUnknown,
} from "@/api";

/** O6 service identity writes (api, setup.md). Org admins only; the token appears ONCE. */
const base = (orgId: string) => `/organizations/${encodeURIComponent(orgId)}/service-identities`;

export type ServiceScope = "organization_admin" | "mission_admin";

export const issuedReader = d.object({
  service_identity: d.object({
    id: d.token,
    name: d.string,
    capabilities: d.array(d.token, 20),
    mission_id: d.nullable(d.token),
  }),
  api_token: d.string,
});
export type Issued = Decoded<typeof issuedReader>;

export function createServiceIdentity(
  orgId: string,
  body: Readonly<{ name: string; scope: ServiceScope; missionId: string | null }>,
): Promise<ApiResult<Issued>> {
  return request(base(orgId), issuedReader, {
    method: "POST",
    body: {
      name: body.name,
      capabilities: [body.scope],
      ...(body.scope === "mission_admin" ? { mission_id: body.missionId } : {}),
    },
  });
}

/** The old token stops working immediately. */
export function rotateServiceIdentity(orgId: string, id: string): Promise<ApiResult<Issued>> {
  return request(`${base(orgId)}/${encodeURIComponent(id)}/rotate`, issuedReader, {
    method: "POST",
    body: {},
  });
}

/** 204: disabled; the token stops working and it leaves the directory. */
export function revokeServiceIdentity(orgId: string, id: string): Promise<ApiResult<null>> {
  return request(`${base(orgId)}/${encodeURIComponent(id)}`, () => null, { method: "DELETE" });
}

export type ServiceFailure = Readonly<{
  text: string | null;
  fields: Readonly<Record<string, string>>;
}>;

/** O6 errors in words; invalid fields inline (name, mission_id); U20 on a dropped connection. */
export function serviceFailure(e: ApiError): ServiceFailure {
  const code = codeOf(e);
  if (code === "invalid_params" && "details" in e && e.details && typeof e.details === "object") {
    const fields: Record<string, string> = {};
    for (const [k, v] of Object.entries(recordOf(e.details) ?? {})) {
      const t = Array.isArray(v) ? v.filter((x) => typeof x === "string").join(" ") : v;
      if (typeof t === "string" && t) fields[k] = t;
    }
    const inline = Object.keys(fields).every((k) => k === "name" || k === "mission_id");
    return { text: inline ? null : "Nothing was created. Check the fields.", fields };
  }
  if (code === "service_identity_not_found")
    return {
      text: "This service identity isn't active any more. The list has been reloaded.",
      fields: {},
    };
  if (e.kind === "forbidden")
    return { text: "Only an organization admin can manage service identities.", fields: {} };
  if (outcomeUnknown(e))
    return {
      text: "No clear answer from the server, so it may or may not have changed. Reload before trying again; a token issued meanwhile can't be shown again, so rotate if you need one.",
      fields: {},
    };
  return { text: `Nothing changed. ${"message" in e ? e.message : ""}`.trim(), fields: {} };
}
