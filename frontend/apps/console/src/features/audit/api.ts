import { decoders, request, type ApiResult, type Decoded } from "@/api";

/** Contract: docs/apogee/api/setup.md, `GET /organizations/:id/audit` (AU1). */
const { array, nullable, object, oneOf, string, timestamp, token } = decoders;

export const auditKinds = ["config", "commanding", "access", "alarms", "contacts", "data"] as const;
export type AuditKind = (typeof auditKinds)[number];

const idText = (v: unknown, path = ""): string | null =>
  typeof v === "number" ? String(v) : nullable(token)(v === undefined ? null : v, path);

const event = object({
  id: token,
  at: timestamp,
  // Settings history carries only the actor's name (id null); some records have no actor.
  actor: nullable(object({ kind: token, id: nullable(token), name: string })),
  kind: oneOf(auditKinds),
  action: string,
  // Revision targets carry their integer number as the id; settings carry the section key.
  target: nullable(object({ kind: token, id: idText, label: string })),
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
  missionId: string | null;
  /** One person's events (AU1 `actor_id`; People › person Activity). */
  actorId?: string;
  /** Window end, fixed per query so later pages read the same window. */
  to: string;
  cursor?: string;
}>;

export function fetchAudit(q: AuditQuery, signal: AbortSignal): Promise<ApiResult<AuditPage>> {
  const to = new Date(q.to);
  const from = new Date(to.getTime() - q.days * 86_400_000);
  const params = new URLSearchParams({ from: from.toISOString(), to: to.toISOString() });
  if (q.kinds.length > 0) params.set("kinds", q.kinds.join(","));
  if (q.missionId) params.set("mission_id", q.missionId);
  if (q.actorId) params.set("actor_id", q.actorId);
  if (q.cursor) params.set("cursor", q.cursor);
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

export type AuditRow = AuditEvent & Readonly<{ repeat: number }>;

/** Identical consecutive actions collapse into one row with a count (Timeline rule). */
export function groupRepeats(events: readonly AuditEvent[]): readonly AuditRow[] {
  const rows: AuditRow[] = [];
  const same = (a: AuditEvent, b: AuditEvent) =>
    a.action === b.action &&
    a.actor?.name === b.actor?.name &&
    a.target?.label === b.target?.label &&
    a.mission?.id === b.mission?.id &&
    a.reason === b.reason;
  for (const e of events) {
    const last = rows.at(-1);
    if (last && same(last, e)) rows[rows.length - 1] = { ...last, repeat: last.repeat + 1 };
    else rows.push({ ...e, repeat: 1 });
  }
  return rows;
}

/** The target, unless the action sentence already names it ("Requested NOOP · NOOP"). */
export function targetText(e: AuditEvent): string | null {
  return e.target && !e.action.includes(e.target.label) ? e.target.label : null;
}

/** "config, commanding and access" */
export function listWords(words: readonly string[]): string {
  return words.length < 2
    ? (words[0] ?? "")
    : `${words.slice(0, -1).join(", ")} and ${words.at(-1) ?? ""}`;
}
