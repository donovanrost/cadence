import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Requested shape: docs/apogee/plans/setup-shapes.md §AU1. */
const { array, nullable, object, oneOf, string, timestamp, token } = decoders;

export const auditKinds = ["config", "commanding", "access", "alarms", "contacts", "data"] as const;
export type AuditKind = (typeof auditKinds)[number];

const event = object({
  id: token,
  at: timestamp,
  actor: object({ kind: oneOf(["user", "service"]), id: token, name: string }),
  kind: oneOf(auditKinds),
  action: string,
  target: nullable(object({ kind: token, id: token, label: string })),
  mission: nullable(object({ id: token, name: string })),
  reason: nullable(string),
});
export const auditReader = object({
  events: array(event, 1000),
  sources: object({
    included: array(oneOf(auditKinds), 10),
    missing: array(oneOf(auditKinds), 10),
  }),
  next_cursor: nullable(string),
});
export type AuditPage = Decoded<typeof auditReader>;
export type AuditEvent = Decoded<typeof event>;

export type AuditQuery = Readonly<{
  organizationId: string;
  days: number;
  kinds: readonly AuditKind[];
}>;

export function fetchAudit(q: AuditQuery, signal: AbortSignal): Promise<ApiResult<AuditPage>> {
  const to = new Date();
  const from = new Date(to.getTime() - q.days * 86_400_000);
  const params = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  if (q.kinds.length > 0) params.set("kinds", q.kinds.join(","));
  return request(
    `/organizations/${encodeURIComponent(q.organizationId)}/audit?${params.toString()}`,
    auditReader,
    { signal },
  );
}

export const kindLabel: Readonly<Record<AuditKind, string>> = {
  config: "Config",
  commanding: "Commanding",
  access: "Access",
  alarms: "Alarms",
  contacts: "Contacts",
  data: "Data",
};
